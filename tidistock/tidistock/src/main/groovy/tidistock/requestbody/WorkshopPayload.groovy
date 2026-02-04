package tidistock.requestbody

import grails.validation.Validateable

import java.time.DayOfWeek
import java.time.LocalDate

class WorkshopPayload  implements Validateable{

    String branchId
    LocalDate date

    static constraints = {
        branchId nullable: false

        date validator: { LocalDate val, obj ->
            if (val?.dayOfWeek != DayOfWeek.SUNDAY) {
                return ['workshopRegistration.date.onlySunday']
            }
        }
    }
}
