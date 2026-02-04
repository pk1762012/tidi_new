package tidistock

import tidistock.enums.SubscriptionType
import tidistock.enums.TransactionStatus


class IosTransaction {

    String id
    TransactionStatus status = TransactionStatus.PENDING
    String transactionId
    Date dateCreated
    Date lastUpdated
    SubscriptionType subscriptionType
    User user

    static constraints = {
        status nullable: false
        transactionId nullable: false, unique: true
        subscriptionType nullable: false
        user nullable: false
    }

    static mapping = {
        id generator: 'uuid'
    }
}
