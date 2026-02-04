package tidistock.requestbody

import tidistock.enums.RewardRedemptionStatus
import grails.validation.Validateable

class RedemptionStatusPayload implements Validateable{

    String redemptionId
    RewardRedemptionStatus redemptionStatus

    static constraints = {
        redemptionId nullable: false
        redemptionStatus nullable: false
    }
}
