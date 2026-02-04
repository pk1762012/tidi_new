package tidistock


import tidistock.requestbody.AdminTransaction
import tidistock.requestbody.CSVFile
import tidistock.requestbody.CourseStatusUpdatePayload
import tidistock.requestbody.CourseTransactionPayload
import tidistock.requestbody.DematEnquiryUpdatePayload
import tidistock.requestbody.GetDematEnquiryPayload
import tidistock.requestbody.GetUsersPayload
import tidistock.requestbody.NotificationPayload
import tidistock.requestbody.NotificationTopicPayload
import grails.plugin.springsecurity.annotation.Secured
import io.micronaut.http.HttpStatus
import tidistock.requestbody.PaginationPayload
import tidistock.requestbody.RevenueStatsPayload
import tidistock.requestbody.WorkshopGetPayload

@Secured('ROLE_ADMIN')
class AdminController {

	static responseFormats = ['json', 'xml']

    def transactionService

	def adminService

    def stockService

	def creditFundToUserWallet(AdminTransaction transaction){
		if(transaction.hasErrors()){
			respond transaction.errors, status: HttpStatus.BAD_REQUEST.getCode()
			return
		}
		def response = transactionService.fundUserWallet(transaction)
		handleResponse(response.status, response.code, response.message)
	}

	def debitFundFromUserWallet(AdminTransaction transaction){
		if(transaction.hasErrors()){
			respond transaction.errors, status: HttpStatus.BAD_REQUEST.getCode()
			return
		}
		def response = transactionService.debitUserWallet(transaction)
		handleResponse(response.status, response.code, response.message)
	}

	def deleteUser(String id) {
		def response = adminService.deleteUser(id)
		handleResponse(response.status, response.code, response.message)
	}

    def enableUser(String id) {
        def response = adminService.enableUser(id)
        handleResponse(response.status, response.code, response.message)
    }

    def disableUser(String id) {
        def response = adminService.disableUser(id)
        handleResponse(response.status, response.code, response.message)
    }

    def getUsers(GetUsersPayload getUsersPayload) {
        if(getUsersPayload.hasErrors()){
            respond getUsersPayload.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond adminService.getUsers(getUsersPayload), status: HttpStatus.OK.getCode()
    }

    def getDashboardStats() {
        respond adminService.getDashboardStats(), status: HttpStatus.OK.getCode()
    }

    def getRevenueStats(RevenueStatsPayload payload) {
        if(payload.hasErrors()){
            respond payload.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond adminService.getRevenueStats(payload), status: HttpStatus.OK.getCode()
    }

    def notifyUser(NotificationPayload payload) {
        if(payload.hasErrors()){
            respond payload.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        def response = adminService.notifyUser(payload)
        handleResponse(response.status, response.code, response.message)
    }

    def notifyTopic(NotificationTopicPayload payload) {
        if(payload.hasErrors()){
            respond payload.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        def response = adminService.notifyTopic(payload)
        handleResponse(response.status, response.code, response.message)
    }

	private void handleResponse(boolean status, int code, String message) {
		def response = [status: status, code: code, message: message]
		respond response, status: code
	}

    def uploadStockData(CSVFile csvFile) {
        if (csvFile.hasErrors()) {
            respond csvFile.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond stockService.uploadStockData(csvFile), status : HttpStatus.OK.getCode()
    }

    def uploadEtfData(CSVFile csvFile) {
        if (csvFile.hasErrors()) {
            respond csvFile.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond stockService.uploadEtfData(csvFile), status : HttpStatus.OK.getCode()
    }

    def uploadNifty50Stocks(CSVFile csvFile) {
        if (csvFile.hasErrors()) {
            respond csvFile.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond stockService.uploadNifty50Stocks(csvFile), status : HttpStatus.OK.getCode()
    }

    def uploadNiftyFNOStocks(CSVFile csvFile) {
        if (csvFile.hasErrors()) {
            respond csvFile.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond stockService.uploadNiftyFNOStocks(csvFile), status : HttpStatus.OK.getCode()
    }

    def uploadHolidayData(CSVFile csvFile) {
        if (csvFile.hasErrors()) {
            respond csvFile.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond stockService.uploadHolidayData(csvFile), status : HttpStatus.OK.getCode()
    }

    def getWorkshopRegistrations(WorkshopGetPayload payload) {
        if(payload.hasErrors()){
            respond payload.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond adminService.getWorkshopRegistrations(payload), status: HttpStatus.OK.getCode()
    }

    def getCourseTransactions(CourseTransactionPayload payload) {
        if(payload.hasErrors()){
            respond payload.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond adminService.getCourseTransactions(payload), status: HttpStatus.OK.getCode()
    }

    def updateCourseStatus(CourseStatusUpdatePayload payload) {
        if(payload.hasErrors()){
            respond payload.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond adminService.updateCourseStatus(payload), status: HttpStatus.OK.getCode()
    }

    def getDematEnquiries(GetDematEnquiryPayload payload) {
        if(payload.hasErrors()){
            respond payload.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond adminService.getDematEnquiries(payload), status: HttpStatus.OK.getCode()
    }

    def updateDematEnquiryStatus(DematEnquiryUpdatePayload payload) {
        if(payload.hasErrors()){
            respond payload.errors, status: HttpStatus.BAD_REQUEST.getCode()
            return
        }
        respond adminService.updateDematEnquiryStatus(payload), status: HttpStatus.OK.getCode()
    }

}
