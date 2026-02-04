package tidistock

import tidistock.enums.OrderType
import tidistock.enums.SubscriptionType

class SubscriptionOrder {

    String id
    Subscription subscription
    String orderId
    OrderType orderType
    String receiptId
    SubscriptionType subscriptionType
    BigDecimal amount

    Date dateCreated
    Date lastUpdated

    static constraints = {
        subscription nullable: false
        orderId nullable: false, unique: true
        orderType nullable: false
        receiptId nullable: false, unique: true
        subscriptionType nullable: false
        amount nullable: false
    }

    static mapping = {
        id generator: 'uuid'
    }
}
