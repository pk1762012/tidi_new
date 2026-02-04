package tidistock

class Course {
    String id
    String name
    BigDecimal bookingPrice
    BigDecimal price
    BigDecimal actualPrice

    static constraints = {
        name nullable: false
        bookingPrice nullable: false
        price nullable: false
        actualPrice nullable: false
    }

    static mapping = {
        id generator: 'uuid'
    }
}
