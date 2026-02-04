package tidistock

import grails.gorm.transactions.Transactional
import io.micronaut.http.HttpStatus
import tidistock.requestbody.DematEnquiryPayload

@Transactional
class DematEnquiryService {

    def addEnquiry(DematEnquiryPayload payload) {

        new DematEnquiry(firstName: payload.firstName, lastName: payload.lastName, phoneNumber: payload.phoneNumber).save(flush : true)
        return [
                status : true,
                code   : HttpStatus.CREATED.getCode(),
        ]
    }
}
