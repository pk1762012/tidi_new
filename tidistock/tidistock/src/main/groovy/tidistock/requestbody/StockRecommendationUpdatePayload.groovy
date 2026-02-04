package tidistock.requestbody

import grails.validation.Validateable

import java.time.LocalDate

class StockRecommendationUpdatePayload implements Validateable{

    BigDecimal triggerPrice
    BigDecimal targetPrice
    BigDecimal stopLoss

    static constraints = {
        targetPrice nullable: false
        triggerPrice nullable: false
        stopLoss nullable: false
    }
}
