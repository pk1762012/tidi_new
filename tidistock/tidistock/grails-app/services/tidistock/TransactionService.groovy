package tidistock


import tidistock.enums.TransactionStatus
import tidistock.enums.TransactionType
import tidistock.requestbody.AdminTransaction
import grails.gorm.transactions.Transactional
import io.micronaut.http.HttpStatus
import org.springframework.context.MessageSource

@Transactional
class TransactionService {

    MessageSource messageSource
    def springSecurityService
    def fireBaseService


    def fundUserWallet(AdminTransaction creditTransaction) {
        def response = [status: false, code: HttpStatus.UNPROCESSABLE_ENTITY.getCode(), message: messageSource.getMessage('transaction.failure', new Object[] { }, Locale.ENGLISH)]
        def (isValidUser, code, message) = validateUser(creditTransaction.userId)
        if(!isValidUser){
            return [status:false, code:code, message: message]
        }
        def user = User.findById(creditTransaction.userId)
        def wallet = user.wallet
        def transaction = new Transaction(
                wallet: wallet,
                amount: creditTransaction.amount,
                amountBeforeTransaction: wallet.balance,
                amountAfterTransaction: wallet.balance.add(creditTransaction.amount),
                transactionType: TransactionType.CREDIT ,
                status: TransactionStatus.SUCCESS ,
                initiatedBy: springSecurityService.currentUser  as User,
                reason: creditTransaction.reason
        )
        if (!transaction.save(flush: true)) {
            response.code = HttpStatus.INTERNAL_SERVER_ERROR.getCode()
            response.message = messageSource.getMessage('transaction.create.failure', new Object[] { }, Locale.ENGLISH)
        } else {
            wallet.setBalance(wallet.balance.add(creditTransaction.amount))
            wallet.save(flush: true)
            response.status = true
            response.code = HttpStatus.OK.getCode()
            response.message = messageSource.getMessage('transaction.create.success', new Object[]{}, Locale.ENGLISH)

            if (user.fcmToken) {
                def title = "Wallet Credited"
                def body = "₹${creditTransaction.amount} has been added to your wallet. Your new balance is ₹${wallet.balance}."
                fireBaseService.sendToToken(user.fcmToken, title, body)
            }
        }
        return response
    }

    def debitUserWallet(AdminTransaction debitTransaction) {
        def response = [status: false, code: HttpStatus.UNPROCESSABLE_ENTITY.getCode(), message: messageSource.getMessage('transaction.failure', new Object[] { }, Locale.ENGLISH)]
        def (isValidUser, code, message) = validateUser(debitTransaction.userId)
        if(!isValidUser){
            return [status:false, code:code, message: message]
        }
        def user = User.findById(debitTransaction.userId)
        def wallet = user.wallet

        if (wallet.balance < debitTransaction.amount) {
            return [
                    status : false,
                    code   : HttpStatus.BAD_REQUEST.getCode(),
                    message: messageSource.getMessage('transaction.insufficient.balance', new Object[]{}, Locale.ENGLISH)
            ]
        }
        def transaction = new Transaction(
                wallet: wallet,
                amount: debitTransaction.amount,
                amountBeforeTransaction: wallet.balance,
                amountAfterTransaction: wallet.balance.subtract(debitTransaction.amount),
                transactionType: TransactionType.DEBIT ,
                status: TransactionStatus.SUCCESS ,
                initiatedBy: springSecurityService.currentUser  as User,
                reason: debitTransaction.reason
        )
        if (!transaction.save(flush: true)) {
            response.code = HttpStatus.INTERNAL_SERVER_ERROR.getCode()
            response.message = messageSource.getMessage('transaction.create.failure', new Object[] { }, Locale.ENGLISH)
        } else {
            wallet.setBalance(wallet.balance.subtract(debitTransaction.amount))
            wallet.save(flush: true)
            response.status = true
            response.code = HttpStatus.OK.getCode()
            response.message = messageSource.getMessage('transaction.create.success', new Object[]{}, Locale.ENGLISH)

            if (user.fcmToken) {
                def title = "Wallet Debited"
                def body = "₹${debitTransaction.amount} has been deducted from your wallet. Your new balance is ₹${wallet.balance}."
                fireBaseService.sendToToken(user.fcmToken, title, body)
            }
        }
        return response
    }


    private Tuple3<Boolean, Integer, String> validateUser(String id) {
        def user = User.findByIdAndEnabled(id,true)
        if(user){
            def isAdmin = UserRole.exists(id, Role.findByAuthority('ROLE_ADMIN').id)
            if(isAdmin) {
                return new Tuple3<>(false, HttpStatus.UNAUTHORIZED.getCode(), messageSource.getMessage('transaction.noAdminFunding', new Object[] { }, Locale.ENGLISH))
            } else {
                return new Tuple3<>(true, HttpStatus.OK.getCode(),null)
            }
        } else {
            return new Tuple3<>(false, HttpStatus.NOT_FOUND.getCode(), messageSource.getMessage('user.doesNotExist', new Object[] { }, Locale.ENGLISH))
        }
    }
}
