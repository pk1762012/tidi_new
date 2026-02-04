package tidistock

import io.micronaut.http.HttpStatus
import tidistock.enums.OrderType
import com.razorpay.Order
import com.razorpay.RazorpayClient
import tidistock.enums.SubscriptionType
import grails.gorm.transactions.Transactional
import grails.plugin.springsecurity.annotation.Secured
import org.apache.commons.codec.binary.Hex
import org.json.JSONObject
import tidistock.requestbody.WorkshopPayload

import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import java.text.SimpleDateFormat

@Transactional
@Secured(["ROLE_USER"])
class RazorpayService {

    def grailsApplication
    RazorpayClient razorpayClient
    def springSecurityService
    def messageSource
    def fireBaseService

    void init() {
        razorpayClient = new RazorpayClient(grailsApplication.config.getProperty("razor_pay.api_key") as String, grailsApplication.config.getProperty("razor_pay.secret_key"))
    }

    def createSubscriptionOrder(SubscriptionType subscriptionType) {
        User user = springSecurityService.getCurrentUser()
        Integer amount = subscriptionType == SubscriptionType.MONTHLY ? 249 : subscriptionType == SubscriptionType.HALF_YEARLY ? 1399 : 2799

        def options = new JSONObject()
        options.put("amount", amount * 100) // amount in paise
        options.put("currency", "INR")
        options.put("receipt", "rct_${UUID.randomUUID().toString()}")
        options.put("payment_capture", 1)

        Order order = razorpayClient.orders.create(options)

        SubscriptionOrder subscriptionOrder = new SubscriptionOrder(subscription: user.wallet.subscription, subscriptionType: subscriptionType, amount: BigDecimal.valueOf(amount), orderId: order.id, receiptId: order.receipt, orderType: OrderType.valueOf((order.status as String).toUpperCase()))
        subscriptionOrder.save(flush:true)
        return [status: true, data: [orderId: subscriptionOrder.orderId, amount: amount * 100]]
    }

    def createCourseOrder(Course course, Branch branch) {
        User user = springSecurityService.getCurrentUser()

        def options = new JSONObject()
        options.put("amount", course.bookingPrice * 100) // amount in paise
        options.put("currency", "INR")
        options.put("receipt", "rct_${UUID.randomUUID().toString()}")
        options.put("payment_capture", 1)

        Order order = razorpayClient.orders.create(options)

        CourseOrder courseOrder = new CourseOrder(user: user, course: course, branch: branch, amount: course.bookingPrice, orderId: order.id, receiptId: order.receipt, orderType: OrderType.valueOf((order.status as String).toUpperCase()))
        courseOrder.save(flush:true)
        return [status: true, data: [orderId: courseOrder.orderId, amount: course.bookingPrice * 100]]
    }

    @Transactional
    def registerToWorkshop(WorkshopPayload payload) {
        User user = springSecurityService.getCurrentUser()
        Branch branch = Branch.findById(payload.branchId)

        if (!branch) {
            return [status: false, code: HttpStatus.BAD_REQUEST.getCode(), message: messageSource.getMessage('workshopRegistration.branch.not.found', new Object[] { }, Locale.ENGLISH)]
        }

        if (WorkshopRegistration.findByDateAndUserAndOrderType(payload.date, user, OrderType.PAID)) {
            return [status: false, code: HttpStatus.BAD_REQUEST.getCode(), message: messageSource.getMessage('workshopRegistration.already.registered', new Object[] { }, Locale.ENGLISH)]
        }

        def amount = Config?.findByName('WORKSHOP_FEE') ? Config?.findByName('WORKSHOP_FEE')?.value?.toInteger() * 100 : 4900
        def options = new JSONObject()
        options.put("amount", amount) // amount in paise
        options.put("currency", "INR")
        options.put("receipt", "rct_${UUID.randomUUID().toString()}")
        options.put("payment_capture", 1)

        Order order = razorpayClient.orders.create(options)

        WorkshopRegistration workshopRegistration = new WorkshopRegistration(user: user, branch: branch, date: payload.date ,amount: new BigDecimal((amount/100)), orderId: order.id, receiptId: order.receipt, orderType: OrderType.valueOf((order.status as String).toUpperCase()))
        workshopRegistration.save(flush: true)
        return  [status: true, code: HttpStatus.CREATED.getCode(), data: [orderId: workshopRegistration.orderId, amount: amount]]

    }

    def paymentWebhook(def payload) {

        def event = payload.event

        if (event == "payment.failed") {
            paymentFailedUpdate(payload.payload.payment.entity)
        } else if (event == "payment.captured") {
            paymentSuccessfulUpdate(payload.payload.payment.entity)
        }

    }

    void paymentFailedUpdate(def paymentData) {
        String orderId = paymentData.order_id
        SubscriptionOrder subscriptionOrder = SubscriptionOrder.findByOrderId(orderId)

        if (subscriptionOrder) {
            subscriptionOrder.setOrderType(OrderType.FAILED)
            subscriptionOrder.save(flush: true)

            User user = User.findByWallet(Wallet.findBySubscription(subscriptionOrder.subscription))

            fireBaseService.sendToToken(
                    user.fcmToken,
                    messageSource.getMessage('razorpay.payment.failure.title', new Object[] { }, Locale.ENGLISH) as String,
                    messageSource.getMessage('razorpay.payment.failure.body', new Object[] { }, Locale.ENGLISH) as String,
            )
        } else {
            CourseOrder courseOrder = CourseOrder.findByOrderId(orderId)
            if (courseOrder) {
                courseOrder.setOrderType(OrderType.FAILED)
                courseOrder.save(flush: true)

                User user = courseOrder.user

                fireBaseService.sendToToken(
                        user.fcmToken,
                        messageSource.getMessage('razorpay.payment.failure.title', new Object[] { }, Locale.ENGLISH) as String,
                        messageSource.getMessage('razorpay.payment.course.failure.body', new Object[] { }, Locale.ENGLISH) as String,
                )
            } else {
                WorkshopRegistration workshopRegistration = WorkshopRegistration.findByOrderId(orderId)

                if (workshopRegistration) {
                    workshopRegistration.setOrderType(OrderType.FAILED)
                    workshopRegistration.save(flush: true)

                    User user = workshopRegistration.user

                    fireBaseService.sendToToken(
                            user.fcmToken,
                            messageSource.getMessage('razorpay.payment.failure.title', new Object[] { }, Locale.ENGLISH) as String,
                            messageSource.getMessage('razorpay.payment.workshop.failure.body', new Object[] { }, Locale.ENGLISH) as String,
                    )
                } else {
                    log.error(messageSource.getMessage('razorpay.webhook.order.not.found', [orderId] as Object[], Locale.ENGLISH))
                }
            }
        }
    }

    void paymentSuccessfulUpdate(def paymentData) {
        String orderId = paymentData.order_id
        BigDecimal amount = BigDecimal.valueOf(paymentData?.amount /100)

        SubscriptionOrder subscriptionOrder = SubscriptionOrder.findByOrderIdAndAmountAndOrderTypeNotEqual(orderId, amount, OrderType.PAID)

        if (subscriptionOrder) {
            subscriptionOrder.setOrderType(OrderType.PAID)
            subscriptionOrder.save(flush: true)

            Subscription subscription = subscriptionOrder.subscription

            Calendar calendar = Calendar.instance
            calendar.time = !subscription.isSubscribed ? new Date() : subscription.expirationDate

            if (subscription.isSubscribed) {
                calendar.add(Calendar.DATE, 1)
            }

            SubscriptionTransaction subscriptionTransaction = new SubscriptionTransaction()
            subscriptionTransaction.subscription = subscription
            subscriptionTransaction.subscriptionType = subscriptionOrder.subscriptionType
            subscriptionTransaction.orderId = subscriptionOrder.orderId
            subscriptionTransaction.amount = subscriptionOrder.amount
            subscriptionTransaction.startDate = calendar.time
            subscriptionTransaction.save(flush: true)


            subscription.isSubscribed = true
            subscription.subscriptionType = subscriptionOrder.subscriptionType

            switch (subscriptionOrder.subscriptionType) {
                case SubscriptionType.MONTHLY:
                    calendar.add(Calendar.MONTH, 1)
                    break
                case SubscriptionType.HALF_YEARLY:
                    calendar.add(Calendar.MONTH, 6)
                    break
                case SubscriptionType.YEARLY:
                    calendar.add(Calendar.YEAR, 1)
                    break
                default:
                    calendar.add(Calendar.MONTH, 1)
            }

            subscription.expirationDate = calendar.time
            subscription.save(flush: true)

            User user = User.findByWallet(Wallet.findBySubscription(subscription))


            if (user.fcmToken) {
                def formatter = new SimpleDateFormat("dd MMM yyyy") // Example: 06 Sep 2025
                def formattedDate = formatter.format(subscription.expirationDate)

                fireBaseService.sendToToken(
                        user.fcmToken,
                        messageSource.getMessage('razorpay.payment.success.title', new Object[] { }, Locale.ENGLISH) as String,
                        messageSource.getMessage('razorpay.payment.success.body', [formattedDate] as Object[], Locale.ENGLISH) as String
                )
            }

        } else {
            CourseOrder courseOrder = CourseOrder.findByOrderIdAndOrderTypeNotEqual(orderId, OrderType.PAID)

            if (courseOrder) {
                courseOrder.setOrderType(OrderType.PAID)
                courseOrder.save(flush: true)

                User user = courseOrder.user


                if (user.fcmToken) {
                    fireBaseService.sendToToken(
                            user.fcmToken,
                            messageSource.getMessage('razorpay.payment.course.success.title', new Object[] { }, Locale.ENGLISH) as String,
                            messageSource.getMessage('razorpay.payment.course.success.body', new Object[] { }, Locale.ENGLISH) as String
                    )
                }

            } else {

                WorkshopRegistration workshopRegistration = WorkshopRegistration.findByOrderIdAndOrderTypeNotEqual(orderId, OrderType.PAID)

                if (workshopRegistration) {
                    workshopRegistration.setOrderType(OrderType.PAID)
                    workshopRegistration.save(flush: true)

                    User user = workshopRegistration.user


                    if (user.fcmToken) {
                        fireBaseService.sendToToken(
                                user.fcmToken,
                                messageSource.getMessage('razorpay.payment.workshop.success.title', new Object[] { }, Locale.ENGLISH) as String,
                                messageSource.getMessage('razorpay.payment.workshop.success.body', new Object[] { }, Locale.ENGLISH) as String
                        )
                    }

                } else {
                    log.error(messageSource.getMessage('razorpay.webhook.order.not.found', [orderId] as Object[], Locale.ENGLISH))
                }
            }
        }
    }


    boolean verifySignature(String body, String signature) {
        try {
            String secret = grailsApplication.config.getProperty("razor_pay.webhook_secret") as String
            Mac sha256Hmac = Mac.getInstance("HmacSHA256")
            SecretKeySpec secretKey = new SecretKeySpec(secret.bytes, "HmacSHA256")
            sha256Hmac.init(secretKey)
            String hash = Hex.encodeHexString(sha256Hmac.doFinal(body.bytes))
            return hash == signature
        } catch (Exception ignored) {
            log.error(messageSource.getMessage('razorpay.webhook.signature.mismatch', new Object[] { }, Locale.ENGLISH))
            return false
        }
    }

}
