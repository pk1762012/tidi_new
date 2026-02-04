package tidistock.requestbody

import grails.validation.Validateable

import java.time.LocalDate

class WorkshopGetPayload  implements Validateable{

    Integer limit
    Integer offset
    String branchId
    LocalDate date

    static constraints = {
        limit nullable: true
        offset nullable: true
        branchId nullable: true
        date nullable: true
    }
}
