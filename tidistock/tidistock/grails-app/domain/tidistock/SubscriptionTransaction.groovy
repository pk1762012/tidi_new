package tidistock

import tidistock.enums.SubscriptionType

class SubscriptionTransaction {

    String id
    Subscription subscription
    String orderId
    SubscriptionType subscriptionType
    BigDecimal amount
    Date startDate

    Date dateCreated
    Date lastUpdated

    static constraints = {
        subscription nullable: false
        orderId nullable: false
        subscriptionType nullable: false
        amount nullable: false
        startDate nullable: false
    }

    static mapping = {
        id generator: 'uuid'
    }
}
