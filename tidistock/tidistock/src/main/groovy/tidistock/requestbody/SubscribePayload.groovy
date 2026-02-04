package tidistock.requestbody

import tidistock.enums.DeviceType
import tidistock.enums.SubscriptionType
import grails.validation.Validateable

class SubscribePayload implements Validateable{

    String transactionId
    SubscriptionType subscriptionType
    DeviceType deviceType
    String productId
    String purchaseToken

    static constraints = {
        transactionId nullable:  true
        subscriptionType nullable: false
        deviceType nullable: false
        purchaseToken nullable: true
        productId nullable: false
    }
}
