package tidistock

import tidistock.enums.SubscriptionType

class Subscription {

    String id
    Boolean isSubscribed = false
    Date expirationDate
    SubscriptionType subscriptionType

    Date dateCreated
    Date lastUpdated

    static constraints = {
        isSubscribed nullable: false
        expirationDate nullable: true
        subscriptionType nullable: true
    }

    static mapping = {
        id generator: 'uuid'
    }
}
