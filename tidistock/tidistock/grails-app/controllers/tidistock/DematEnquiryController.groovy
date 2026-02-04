package tidistock

import io.micronaut.http.HttpStatus
import org.springframework.security.access.annotation.Secured
import tidistock.requestbody.DematEnquiryPayload


class DematEnquiryController {

    def dematEnquiryService

    @Secured('permitAll')
    def addEnquiry(DematEnquiryPayload payload) {
        if (payload.hasErrors()) {
            respond payload.errors, status: HttpStatus.BAD_REQUEST.getCode()
        }
        def response =  dematEnquiryService.addEnquiry(payload)
        respond response, status: response.code
    }
}
