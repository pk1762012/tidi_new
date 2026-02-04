package tidistock.requestbody

import tidistock.enums.TransactionType
import grails.validation.Validateable

class TransactionPayload implements Validateable{

    Date date
    Integer limit
    Integer offset
    TransactionType transactionType

    static constraints = {
        date nullable: true
        transactionType nullable: true
        limit nullable: true
        offset nullable: true
    }
}

