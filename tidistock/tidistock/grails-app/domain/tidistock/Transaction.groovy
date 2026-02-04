package tidistock

import tidistock.enums.TransactionStatus
import tidistock.enums.TransactionType

class Transaction {

    String id
    Wallet wallet
    BigDecimal amount
    BigDecimal amountBeforeTransaction
    BigDecimal amountAfterTransaction
    TransactionType transactionType
    TransactionStatus status = TransactionStatus.SUCCESS
    User initiatedBy
    String reason
    Date dateCreated
    Date lastUpdated

    static constraints = {
        wallet nullable: false
        amount nullable: false, min: BigDecimal.ONE
        amountBeforeTransaction nullable: false
        amountAfterTransaction nullable: false
        transactionType nullable: false
        status nullable: false
        initiatedBy nullable: false
        reason nullable: true
    }

    static mapping = {
        id generator: 'uuid'
    }
}
