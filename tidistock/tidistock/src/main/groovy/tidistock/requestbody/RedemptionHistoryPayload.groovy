package tidistock.requestbody

import tidistock.enums.RewardRedemptionStatus
import grails.validation.Validateable

class RedemptionHistoryPayload implements  Validateable {

    Integer limit
    Integer offset
    RewardRedemptionStatus status
    String search
    String sortField
    String sortOrder


    static constraints = {
        limit nullable: true
        offset nullable: true
        status nullable: true
        search nullable: true
        sortField nullable: true
        sortOrder nullable: true
    }
}
