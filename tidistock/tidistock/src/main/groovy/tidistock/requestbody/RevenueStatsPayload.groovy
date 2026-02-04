package tidistock.requestbody

import grails.validation.Validateable

import java.time.LocalDate

class RevenueStatsPayload  implements Validateable{
    LocalDate startDate
    LocalDate endDate

    static constraints = {
        startDate nullable: true
        endDate nullable: true
    }

}
