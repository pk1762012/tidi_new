package tidistock.requestbody

import grails.validation.Validateable
import tidistock.enums.StockRecommendationStatus
import tidistock.enums.StockRecommendationType

class GetStockRecommendationPayload implements Validateable{
    Integer limit
    Integer offset
    String stock
    StockRecommendationStatus status
    StockRecommendationType type
    String sortField
    String sortOrder

    static constraints = {
        limit nullable: true
        offset nullable: true
        stock nullable: true
        status nullable: true
        type nullable: true
        sortField nullable: true
        sortOrder nullable: true
    }
}
