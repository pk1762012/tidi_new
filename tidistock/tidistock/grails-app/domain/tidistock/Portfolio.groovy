package tidistock

class Portfolio {

    String id
    String stockName
    String stockSymbol
    Date dateCreated
    Date lastUpdated

    static constraints = {
        stockName nullable: false
        stockSymbol nullable: false
    }

    static mapping = {
        id generator: 'uuid'
    }
}
