package tidistock.requestbody

import grails.validation.Validateable
import tidistock.enums.StockRecommendationType

import java.time.LocalDate

class StockRecommendationPayload  implements Validateable{

    LocalDate startDate
    LocalDate closedDate
    String stock
    BigDecimal triggerPrice
    BigDecimal targetPrice
    BigDecimal stopLoss
    StockRecommendationType type

    static constraints = {
        startDate nullable: false
        closedDate nullable: true
        stock nullable: false, blank: false, maxSize: 50
        targetPrice nullable: false
        triggerPrice nullable: false
        stopLoss nullable: false
        type nullable: false
    }

}
