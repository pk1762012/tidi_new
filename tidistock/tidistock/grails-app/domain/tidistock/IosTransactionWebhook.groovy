package tidistock

import tidistock.enums.SubscriptionType
import tidistock.enums.TransactionStatus

class IosTransactionWebhook {

    String id
    TransactionStatus status = TransactionStatus.PENDING
    String transactionId
    Date dateCreated
    Date lastUpdated
    SubscriptionType subscriptionType

    static constraints = {
        status nullable: false
        transactionId nullable: false, unique: true
        subscriptionType nullable: true
    }

    static mapping = {
        id generator: 'uuid'
    }
}
