package tidistock.requestbody

import grails.validation.Validateable
import tidistock.enums.DematEnquiryStatus

import java.time.LocalDate

class GetDematEnquiryPayload   implements Validateable  {
    Integer limit
    Integer offset
    String search
    LocalDate date
    DematEnquiryStatus status

    static constraints = {
        limit nullable: true
        offset nullable: true
        search nullable: true
        date nullable: true
        status nullable: true
    }
}
