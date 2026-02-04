package tidistock

class ETF {

    String name
    String symbol
    String underlying

    static constraints = {
        name nullable: false, blank: false
        symbol nullable: false, blank: false
        underlying nullable: false, blank: false


    }
}
