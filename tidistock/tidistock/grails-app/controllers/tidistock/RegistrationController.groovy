package tidistock

import tidistock.requestbody.CreateUser
import io.micronaut.http.HttpStatus
import org.springframework.security.access.annotation.Secured

class RegistrationController {
	static responseFormats = ['json']

    def userService

    @Secured('permitAll')
    def create(CreateUser createUser) {
        if (createUser.hasErrors()) {
            respond createUser.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        User user = User.findByUsername(createUser.phone_number)
        if (User.findByUsername(createUser.phone_number)) {
            respond userService.triggerUserVerification(user)
        } else {
            respond userService.createUser(createUser), status: HttpStatus.CREATED.getCode()
        }
    }

    @Secured('permitAll')
    def verifyUser(String userName, Long otp) {
        def response = userService.verifyUser(userName, otp)
        respond response, status: response.code
    }

    @Secured('permitAll')
    def login(String phoneNumber) {
        respond userService.login(phoneNumber)
    }

    @Secured('permitAll')
    def validateUser(String phoneNumber) {
        boolean valid = userService.validateUser(phoneNumber)
        respond valid, status: valid ? HttpStatus.OK.code : HttpStatus.NOT_FOUND.code
    }

    @Secured('permitAll')
    def getBranches() {
        def response = userService.getBranches()
        respond response, status: response.code
    }

    @Secured('permitAll')
    def getCourses() {
        def response = userService.getCourses()
        respond response, status: response.code
    }
}
