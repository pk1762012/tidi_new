package tidistock

import io.micronaut.http.HttpStatus
import org.springframework.security.access.annotation.Secured
import tidistock.requestbody.GetStockRecommendationPayload
import tidistock.requestbody.PaginationPayload
import tidistock.requestbody.StockRecommendationPayload
import tidistock.requestbody.StockRecommendationUpdatePayload

@Secured(['ROLE_ADMIN', 'ROLE_USER'])
class StockController {

    def stockService

    @Secured(['ROLE_ADMIN', 'ROLE_USER'])
    def searchStock(String query) {
        respond stockService.searchStock(query), status : HttpStatus.OK.getCode()
    }

    @Secured(['ROLE_ADMIN', 'ROLE_USER'])
    def searchEtf(String query) {
        respond stockService.searchEtf(query), status : HttpStatus.OK.getCode()
    }

    @Secured(['ROLE_ADMIN', 'ROLE_USER'])
    def getHolidayList() {
        respond stockService.getHolidayList(), status: HttpStatus.OK.getCode()
    }

    @Secured(['ROLE_ADMIN'])
    def createStockRecommendation(StockRecommendationPayload payload) {
        if(payload.hasErrors()){
            respond payload.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        def response = stockService.createStockRecommendation(payload)
        respond response, status: response.code
    }

    @Secured(['ROLE_ADMIN'])
    def updateStockRecommendation(String id, StockRecommendationUpdatePayload payload) {
        if(payload.hasErrors()){
            respond payload.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        def response = stockService.updateStockRecommendation(id, payload)
        respond response, status: response.code
    }

    @Secured(['ROLE_ADMIN'])
    def bookStockRecommendation(String id, String price) {
        def response = stockService.bookStockRecommendation(id, new BigDecimal(price))
        respond response, status: response.code
    }

    @Secured(['ROLE_ADMIN'])
    def deleteStockRecommendation(String id) {
        def response = stockService.deleteStockRecommendation(id)
        respond response, status: response.code
    }

    @Secured(['ROLE_ADMIN', 'ROLE_USER'])
    def getStockRecommendations(GetStockRecommendationPayload payload) {
        if(payload.hasErrors()){
            respond payload.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond stockService.getStockRecommendations(payload), status: HttpStatus.OK.getCode()
    }

    @Secured(['ROLE_ADMIN'])
    def createPortfolioStock(String stockSymbol) {
        def response = stockService.createPortfolioStock(stockSymbol)
        respond response, status: response.code
    }

    @Secured(['ROLE_ADMIN'])
    def deletePortfolioStock(String id) {
        def response = stockService.deletePortfolioStock(id)
        respond response, status: response.code
    }

    @Secured(['ROLE_ADMIN', 'ROLE_USER'])
    def getStockPortfolio() {
        respond stockService.getStockPortfolio(), status: HttpStatus.OK.getCode()
    }

    @Secured(['ROLE_ADMIN', 'ROLE_USER'])
    def getPortfolioHistory(PaginationPayload paginationPayload) {
        if (paginationPayload.hasErrors()) {
            respond paginationPayload.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond stockService.getPortfolioHistory(paginationPayload), status: HttpStatus.OK.getCode()
    }

    @Secured(['ROLE_ADMIN', 'ROLE_USER'])
    def getIPOData() {
        respond stockService.getIPODataList(), status: HttpStatus.OK.getCode()
    }

    @Secured(['ROLE_ADMIN', 'ROLE_USER'])
    def getFIIData(PaginationPayload paginationPayload) {
        if (paginationPayload.hasErrors()) {
            respond paginationPayload.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond stockService.getFIIData(paginationPayload), status: HttpStatus.OK.getCode()
    }
}
