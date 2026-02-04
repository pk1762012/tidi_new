package tidistock

class BootStrap {

    def userService
    def s3Service
    def fireBaseService
    def razorpayService


    def init = { servletContext ->
        userService.initializeRolesAndUsers()
        s3Service.init()
        fireBaseService.init()
        razorpayService.init()
    }
    def destroy = {
    }
}
