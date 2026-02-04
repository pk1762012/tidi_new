package tidistock

class Wallet {

    String id
    BigDecimal balance = BigDecimal.ZERO
    Boolean isDisabled = false
    Subscription subscription
    Date dateCreated
    Date lastUpdated

    static constraints = {
       balance nullable: false,  min: BigDecimal.ZERO
        isDisabled nullable: false
        subscription nullable: false, unique: true
    }
    static  mapping = {
        id generator: 'uuid'
    }
}
