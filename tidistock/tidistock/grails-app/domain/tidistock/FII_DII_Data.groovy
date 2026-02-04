package tidistock

import java.time.LocalDate

class FII_DII_Data {

    String id
    BigDecimal fiiBuy
    BigDecimal fiiSell
    BigDecimal diiBuy
    BigDecimal diiSell
    LocalDate date

    static constraints = {
        fiiBuy nullable: false
        fiiSell nullable: false
        diiBuy nullable: false
        diiSell nullable: false
        date nullable: false, unique: true
    }

    static mapping = {
        id generator: 'uuid'
    }
}
