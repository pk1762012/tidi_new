package tidistock

import tidistock.enums.PortfolioLogAction

class PortfolioLog {

    String id
    String stockName
    String stockSymbol
    Date dateCreated
    PortfolioLogAction action

    static constraints = {
        stockName nullable: false
        stockSymbol nullable: false
        action nullable: false
    }

    static mapping = {
        id generator: 'uuid'
    }
}
