package tidistock

import tidistock.enums.StockRecommendationStatus
import tidistock.enums.StockRecommendationType

import java.time.LocalDate

class StockRecommend {

    String id
    LocalDate startDate
    LocalDate closedDate
    String stockName
    String stockSymbol
    BigDecimal triggerPrice
    BigDecimal targetPrice
    BigDecimal stopLoss
    BigDecimal bookedPrice
    StockRecommendationStatus stockRecommendationStatus
    Date dateCreated
    Date lastUpdated
    StockRecommendationType type = StockRecommendationType.MEDIUM_TERM


    static constraints = {
        stockName nullable: false
        stockSymbol nullable: false
        startDate nullable: false
        closedDate nullable: true
        triggerPrice nullable: false
        targetPrice nullable: true
        stopLoss nullable: true
        bookedPrice nullable: true
        stockRecommendationStatus nullable: false
        type nullable: false
    }

    static mapping = {
        id generator: 'uuid'
        stockSymbol index: 'idx_stock_recommend_symbol'
        stockRecommendationStatus index: 'idx_stock_recommend_status'
    }
}
