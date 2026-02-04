package tidistock

import io.micronaut.http.HttpStatus
import org.springframework.security.access.annotation.Secured
import grails.converters.JSON

@Secured(['ROLE_ADMIN', 'ROLE_USER'])
class RazorpayController {

    static allowedMethods = [razorpay: "POST"]

    def razorpayService



    @Secured('permitAll')
    def paymentWebhook() {

        def requestBody = request.reader.text
        def receivedSignature = request.getHeader("X-Razorpay-Signature")

        if (razorpayService.verifySignature(requestBody, receivedSignature)) {
            razorpayService.paymentWebhook(JSON.parse(requestBody))
        }

        respond status: HttpStatus.CREATED.getCode()
    }


}
