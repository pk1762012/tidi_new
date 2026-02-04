package tidistock.requestbody

import grails.validation.Validateable

class AdminTransaction  implements Validateable{

    String userId
    BigDecimal amount
    String reason

    static constraints = {
        userId nullable: false, blank: false
        amount nullable: false, min: BigDecimal.ONE
        reason nullable: true
    }
}
