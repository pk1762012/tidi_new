package tidistock

class Nifty50Stock {

    String name
    String symbol

    static constraints = {
        name nullable: false, blank: false
        symbol nullable: false, blank: false

    }
}
