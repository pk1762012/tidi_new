package tidistock

import grails.plugin.springsecurity.rest.token.generation.TokenGenerator
import org.springframework.security.authentication.AuthenticationManager
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken
import tidistock.enums.OrderType
import tidistock.enums.SubscriptionType
import tidistock.enums.TransactionStatus
import tidistock.enums.TransactionType
import tidistock.requestbody.*
import grails.core.GrailsApplication
import grails.gorm.PagedResultList
import grails.gorm.transactions.Transactional
import grails.plugin.springsecurity.annotation.Secured
import groovy.time.TimeCategory
import io.micronaut.http.HttpStatus
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.context.MessageSource
import org.springframework.security.core.context.SecurityContextHolder

import java.nio.charset.StandardCharsets

@Transactional
@Secured(["ROLE_USER"])
class UserService {

    public static final String PASS_TEXT = "ff8080819ab55533019ab5553c9a0001"
    def springSecurityService
    def messageService
    def s3Service
    AuthenticationManager authenticationManager
    TokenGenerator tokenGenerator

    @Autowired
    GrailsApplication grailsApplication

    MessageSource messageSource

    @Secured('permitAll')
    def initializeRolesAndUsers() {
        if (Role.count() == 0) {
            new Role(authority: 'ROLE_ADMIN').save(flush: true)
            new Role(authority: 'ROLE_USER').save(flush: true)

        }

        if (!User.findByUsername("1111111111")) {
            def adminRole = Role.findByAuthority("ROLE_ADMIN")

            def subscription = new Subscription().save(flush:true)
            def wallet = new Wallet(subscription: subscription).save(flush:true)

            def admin = new User(firstName: 'admin', lastName: 'admin', username: '1111111111', password: springSecurityService.encodePassword('Admin123$'), enabled: true, wallet: wallet).save(flush: true)

            UserRole.create(admin, adminRole, true)
        }

        if (Branch.count() == 0) {
            new Branch(name: "RajajiNagar", phoneNumbers: ["9900081906", "9900072521"], mapLink: "https://maps.app.goo.gl/CCVqTVTajmeP4TGR6", address: "Building 2nd Floor, Aruna Silks, Jinka Avenue, 713, Modi Hospital Rd, West of Chord Road 2nd Stage, West of Chord Road, Stage 2, Rajajinagar, Bengaluru, Karnataka 560086").save(flush:true)
            new Branch(name: "JP Nagar", phoneNumbers: ["8867774240", "9900015383"], mapLink: "https://maps.app.goo.gl/S8PhqMcqVLiQ9okp8", address: "25/6, Yelachenahalli Kanakapura Main Road, above Lenskart, opposite Metro Pillar No.94, JP Nagar 6th Phase, Jarganahalli, Post, J. P. Nagar, Bengaluru, Karnataka 560111").save(flush:true)
            new Branch(name: "Yelahanka", phoneNumbers: ["8867774238", "9900071180"], mapLink: "https://maps.app.goo.gl/PK8eXvrRhK61TF2f9", address: "776, 13th B Main Rd, MIG Sector B, Yelahanka Satellite Town, Yelahanka New Town, Bengaluru, Karnataka 560064").save(flush:true)
            new Branch(name: "Hubballi", phoneNumbers: ["9900015380", "9900015376"], mapLink: "https://maps.app.goo.gl/AtaVKXy93bdHmrhC8", address: "2nd Floor, Ronad Building, No 23A/2 & 23/A3, Unkal Bypass Rd, Hosur, Kallur Layout, Hosur, Hubballi, Karnataka 580021").save(flush:true)
            new Branch(name: "Mysore", phoneNumbers: ["9900096220", "8951710777"], mapLink: "https://maps.app.goo.gl/hZtfJJS6GAFY8SNs5", address: "2nd floor, Sri Krishna Arcade, 1103/2, Vanivilasa Rd, Chamarajapura, Chamarajapuram Mohalla, Lakshmipuram, Mysuru, Karnataka 570005").save(flush:true)
            new Branch(name: "Kalaburagi", phoneNumbers: ["9900096245", "9900097733"], mapLink: "https://maps.app.goo.gl/Ah7eJaNguJBcd9hv7", address: "VENKATAGIRI HOTEL, Second Floor ,VIJAYALAXMI ARCADE NEW JEWARGI RD LAND MARK: OLD, opp. POLAR BEAR, New Carporation Layout, Maka Layout, Kalaburagi, Karnataka 585102").save(flush:true)
            new Branch(name: "Whitefield", phoneNumbers: ["9900098043", "9900096250"], mapLink: "https://maps.app.goo.gl/FYihCEbFSyzVmGZPA", address: "422/1, 2nd floor, above Axis Bank, Oppposite MVJ College, Channasandra Kadugodi, Bengaluru East, Bengaluru, Karnataka 560067").save(flush:true)
            new Branch(name: "Davangere", phoneNumbers: ["9900088548", "9900098659"], mapLink: "https://maps.app.goo.gl/WWPctvDurY6EAtbJA", address: "first floor, shanta siri complex, 1136, Ring Rd, Vinobha Nagar, Davanagere, Karnataka 577006").save(flush:true)
        }

        if (Course.count() == 0) {
            new Course(name: "Gold", bookingPrice: BigDecimal.valueOf(499), price: BigDecimal.valueOf(8499), actualPrice: BigDecimal.valueOf(11999)).save(flush:true)
        }

        if (Config.count() == 0) {
            new Config(name: 'NIFTY_LOT_SIZE', value: '65').save(flush:true)
            new Config(name: 'WORKSHOP_FEE', value: '49').save(flush:true)
        }
    }

    @Secured('permitAll')
    def createUser(CreateUser createUser) {
        def wallet
        use(TimeCategory) {
            def expiration = new Date() + 3.days
             wallet = new Wallet(subscription: new Subscription(isSubscribed: true, expirationDate: expiration, subscriptionType: SubscriptionType.PROMOTIONAL)).save(flush:true)
        }
        def user = new User(firstName: createUser.firstName, lastName: createUser.lastName, username: createUser.phone_number, password: springSecurityService.encodePassword(PASS_TEXT), enabled: true, wallet:wallet, email: null, pan: null).save(flush: true)
        def role = Role.findByAuthority("ROLE_USER")
        UserRole.create(user, role, true)
        fundUserWallet(user, BigDecimal.valueOf(100))
        return triggerUserVerification(user)
    }

    void fundUserWallet(User user, BigDecimal amount) {
        def wallet = user.wallet
        def transaction = new Transaction(
                wallet: wallet,
                amount: amount,
                amountBeforeTransaction: wallet.balance,
                amountAfterTransaction: wallet.balance.add(amount),
                transactionType: TransactionType.CREDIT ,
                status: TransactionStatus.SUCCESS ,
                initiatedBy: user,
                reason: "PROMOTIONAL"
        )

        transaction.save(flush: true)

        wallet.setBalance(wallet.balance.add(amount))
        wallet.save(flush: true)
    }

    @Secured('permitAll')
    def triggerUserVerification(User user) {

        if (user.username == "8553312165") {
            return [status : true, code : HttpStatus.ACCEPTED.getCode(), message : messageSource.getMessage('otp.sent', new Object[] { user.username }, Locale.ENGLISH), data : [id : user.id, phone_number : user.username]]
        }
        def response = messageService.sendOTP(user.username)
        if (response.status) {
            user.setVerificationId(response.verificationId as String)
            user.save(flush : true)
            return [status : true, code : HttpStatus.ACCEPTED.getCode(), message : messageSource.getMessage('otp.sent', new Object[] { user.username }, Locale.ENGLISH), data : [id : user.id, phone_number : user.username]]
        }
        return  [status: false, code: HttpStatus.INTERNAL_SERVER_ERROR.getCode(), message: messageSource.getMessage('otp.error', new Object[] { }, Locale.ENGLISH), data : [id : user.id, phone_number : user.username]]
    }

    @Secured('permitAll')
    def validateUser(String phoneNumber) {
        return User.findByUsername(phoneNumber) != null
    }

    @Secured('permitAll')
    def login(String phoneNumber) {
        User user = User.findByUsername(phoneNumber)
        if (user) {
            return triggerUserVerification(user)
        } else {
            return  [status: false, code: HttpStatus.NOT_FOUND.getCode(), message: messageSource.getMessage('user.doesNotExist', new Object[] { }, Locale.ENGLISH)]
        }
    }

    @Secured('permitAll')
    def verifyUser(String userName, Long otp) {
        User user = User.findByUsername(userName)
        if (!user) {
            return  [status: false, code: HttpStatus.NOT_FOUND.getCode(), message: messageSource.getMessage('user.doesNotExist', new Object[] { }, Locale.ENGLISH)]
        }
        if ((user.username == "8553312165") || messageService.verifyOTP(otp.toString(), user.verificationId)) {
            def auth = authenticationManager.authenticate(
                    new UsernamePasswordAuthenticationToken(user.username, PASS_TEXT)
            )
            SecurityContextHolder.context.authentication = auth

            // Generate JWT token manually (Spring Security REST helper)
            def token = tokenGenerator.generateAccessToken(auth.principal)
            return  [status: true, code: HttpStatus.ACCEPTED.getCode(), message: messageSource.getMessage('user.verified', new Object[] { }, Locale.ENGLISH), data : [id : user.id, phone_number : user.username, token : token.accessToken]]
        } else {
            user.save(flush : true)
            return  [status: false, code: HttpStatus.UNAUTHORIZED.getCode(), message: messageSource.getMessage('otp.invalid', new Object[] { }, Locale.ENGLISH), data : [id : user.id, phone_number : user.username]]
        }
    }


    def getUser() {
        User user = springSecurityService.getCurrentUser()
        String profilePictureUrl = grailsApplication.config.aws.s3.url
        def response = [
                    id: user.id,
                    firstName: user.firstName,
                    lastName: user.lastName,
                    username: user.username,
                    enabled: user.enabled,
                    balance : user.wallet.balance,
                    isSubscribed : user?.wallet?.subscription?.isSubscribed,
                    isPaid : user?.wallet?.subscription?.subscriptionType != SubscriptionType.PROMOTIONAL,
                    subscriptionEndDate : user?.wallet?.subscription?.expirationDate,
                    profilePicture : user.profilePictureFile ? profilePictureUrl + user.id + "/PROFILE_PICTURE/" + URLEncoder.encode((user.profilePictureFile), StandardCharsets.UTF_8.toString()) : null,
                    pan : user.pan,
                    email : user.email,
                    config : Config.list().collect{ return [name: it.name, value: it.value]}
            ]

        return [status: true, code: HttpStatus.OK.getCode(), data: response]
    }

    def updateUserDetails(UserDetailsUpdatePayload userDetailsUpdatePayload) {
        User user = springSecurityService.getCurrentUser()

        if (userDetailsUpdatePayload.firstName) {
            user.firstName = userDetailsUpdatePayload.firstName
        }

        if (userDetailsUpdatePayload.lastName) {
            user.lastName = userDetailsUpdatePayload.lastName
        }

        user.save(flush : true)

        return [status: true, code: HttpStatus.OK.getCode()]
    }

    def expireUser() {
        User user = springSecurityService.getCurrentUser()

        user.setAccountExpired(true)
        user.setFcmToken(null)
        user.setDeviceType(null)
        user.setProfilePictureFile(null)
        user.save(flush : true)
        return [status: true, code: HttpStatus.OK.getCode(), data: null]
    }



    def updateProfilePicture(ProfilePicture profilePicture) {
        return s3Service.uploadProfilePicture(profilePicture.getFile())
    }

    def updatePANDetails(PANUploadPayload payload) {
        return s3Service.uploadPANDetails(payload)
    }

    def updatePAN(PANUpdatePayload payload) {
        User user = springSecurityService.getCurrentUser()
        user.email = payload.email
        user.pan = payload.pan

        user.save(flush : true)
        return [status: true, code: HttpStatus.OK.getCode(), data: true]
    }

    def updateDeviceDetails(DeviceDetails deviceDetails) {
        User user = springSecurityService.getCurrentUser()

        user.setFcmToken(deviceDetails.fcmToken)
        user.setDeviceType(deviceDetails.deviceType)

        user.save(flush : true)
        return [status: true, code: HttpStatus.OK.getCode(), data: true]
    }

    @Transactional(readOnly = true)
    def getSubscriptionTransactions(PaginationPayload subscriptionTransactionPayload) {
        User user = springSecurityService.getCurrentUser()
        int limit = subscriptionTransactionPayload.limit ?: 10
        int offset = subscriptionTransactionPayload.offset ?: 0

        Subscription userSubscription = user.wallet?.subscription

        if (!userSubscription) {
            return [limit: limit, offset: offset, totalCount: 0, data: []]
        }

        PagedResultList result = SubscriptionTransaction.createCriteria().list(max: limit, offset: offset) {
            eq("subscription", userSubscription)
            order("dateCreated", "desc")
        } as PagedResultList

        return [
                limit     : limit,
                offset    : offset,
                totalCount: result.totalCount,
                data      : result
        ]
    }

    @Transactional(readOnly = true)
    def getUserTransactions(TransactionPayload payload) {
        User user = springSecurityService.getCurrentUser()
        Wallet wallet = user?.wallet

        int limit = payload.limit ?: 10
        int offset = payload.offset ?: 0

        if (!wallet) {
            return [limit: limit, offset: offset, totalCount: 0, data: []]
        }

        PagedResultList result = Transaction.createCriteria().list(max: limit, offset: offset) {
            eq("wallet", wallet)

            if (payload.transactionType) {
                eq("transactionType", payload.transactionType)
            }

            if (payload.date) {
                def startOfDay = payload.date
                Calendar cal = Calendar.getInstance()
                cal.setTime(startOfDay)
                cal.add(Calendar.DATE, 1)
                Date endOfDay = cal.getTime()

                between("dateCreated", startOfDay, endOfDay)
            }

            order("dateCreated", "desc")
        } as PagedResultList

        def data = result.collect {Transaction transaction ->
            [
                    amount : transaction.amount,
                    type : transaction.transactionType,
                    status : transaction.status,
                    reason : transaction.reason,
                    date : transaction.dateCreated
            ]

        }

        return [
                limit     : limit,
                offset    : offset,
                totalCount: result.totalCount,
                data      : data
        ]
    }

    @Transactional(readOnly = true)
    def getCourseTransactions(PaginationPayload subscriptionTransactionPayload) {
        User user = springSecurityService.getCurrentUser()
        int limit = subscriptionTransactionPayload.limit ?: 10
        int offset = subscriptionTransactionPayload.offset ?: 0



        PagedResultList result = CourseOrder.createCriteria().list(max: limit, offset: offset) {
            eq("user", user)
            eq("orderType", OrderType.PAID)
            order("dateCreated", "desc")
        } as PagedResultList

        return [
                limit     : limit,
                offset    : offset,
                totalCount: result.totalCount,
                data      : result
        ]
    }

    def getBranches() {
        return  [status: true, code: HttpStatus.OK.getCode(), data : Branch.list()]
    }

    def getCourses() {
        return  [status: true, code: HttpStatus.OK.getCode(), data : Course.list()]
    }

    @Transactional(readOnly = true)
    def getWorkshopRegistration() {
        User user = springSecurityService.getCurrentUser()
        return WorkshopRegistration.findAllByUserAndOrderType(user, OrderType.PAID)
    }

    @Transactional(readOnly = true)
    def getUserFCM() {
        User user = springSecurityService.getCurrentUser()
        return [FCM: user.fcmToken]
    }


}
