package tidistock

import tidistock.enums.SubscriptionType
import tidistock.requestbody.*
import io.micronaut.http.HttpStatus
import org.springframework.security.access.annotation.Secured

@Secured('ROLE_USER')
class UserController {
	static responseFormats = ['json', 'xml']

    def userService
    def razorpayService
	
    def getUser() {
        respond userService.getUser(), status : HttpStatus.OK.getCode()
    }

    def updateUserDetails(UserDetailsUpdatePayload userDetailsUpdatePayload) {
        if (userDetailsUpdatePayload.hasErrors()) {
            respond userDetailsUpdatePayload.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond userService.updateUserDetails(userDetailsUpdatePayload), status : HttpStatus.OK.getCode()
    }

    def expireUser() {
        respond userService.expireUser(), status : HttpStatus.OK.getCode()
    }

    def updateProfilePicture(ProfilePicture profilePicture) {
        if (profilePicture.hasErrors()) {
            respond profilePicture.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond userService.updateProfilePicture(profilePicture), status : HttpStatus.OK.getCode()
    }

    def updatePANDetails(PANUploadPayload payload) {
        if (payload.hasErrors()) {
            respond payload.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond userService.updatePANDetails(payload), status : HttpStatus.OK.getCode()
    }

    def updatePAN(PANUpdatePayload payload) {
        if (payload.hasErrors()) {
            respond payload.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond userService.updatePAN(payload), status : HttpStatus.OK.getCode()
    }

    def updateDeviceDetails(DeviceDetails deviceDetails) {
        if (deviceDetails.hasErrors()) {
            respond deviceDetails.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond userService.updateDeviceDetails(deviceDetails), status : HttpStatus.OK.getCode()
    }

    def createSubscriptionOrder(String subscriptionType) {
        try {
            def type = SubscriptionType.valueOf(subscriptionType.toUpperCase())
            respond razorpayService.createSubscriptionOrder(type), status : HttpStatus.CREATED.getCode()
        } catch (IllegalArgumentException e) {
            def response = [status: true, code: HttpStatus.BAD_REQUEST.getCode()]
            respond response, status: HttpStatus.BAD_REQUEST.getCode()
        }
    }

    def getSubscriptionTransactions(PaginationPayload subscriptionTransactionPayload) {
        if (subscriptionTransactionPayload.hasErrors()) {
            respond subscriptionTransactionPayload.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond userService.getSubscriptionTransactions(subscriptionTransactionPayload), status: HttpStatus.OK.getCode()
    }

    def getUserTransactions(TransactionPayload transactionPayload) {
        if (transactionPayload.hasErrors()) {
            respond transactionPayload.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond userService.getUserTransactions(transactionPayload), status: HttpStatus.OK.getCode()
    }

    def createCourseOrder(String courseId, String branchId) {

        def course = Course.findById(courseId)
        def branch = Branch.findById(branchId)
        if (course && branch) {
            respond razorpayService.createCourseOrder(course, branch), status : HttpStatus.CREATED.getCode()
        } else {
            def response = [status: true, code: HttpStatus.BAD_REQUEST.getCode()]
            respond response, status: HttpStatus.BAD_REQUEST.getCode()
        }

    }

    def getCourseTransactions(PaginationPayload subscriptionTransactionPayload) {
        if (subscriptionTransactionPayload.hasErrors()) {
            respond subscriptionTransactionPayload.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond userService.getCourseTransactions(subscriptionTransactionPayload), status: HttpStatus.OK.getCode()
    }

    def registerToWorkshop(WorkshopPayload payload) {

        if (payload.hasErrors()) {
            respond payload.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        def response =  razorpayService.registerToWorkshop(payload)
        respond response, status: response.code

    }

    def getWorkshopRegistration() {
        respond userService.getWorkshopRegistration(), status: HttpStatus.OK.getCode()

    }

    def getUserFCM() {
        respond userService.getUserFCM(), status: HttpStatus.OK.getCode()

    }
}
