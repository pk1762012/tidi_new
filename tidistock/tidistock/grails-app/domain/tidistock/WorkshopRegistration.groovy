package tidistock

import tidistock.enums.OrderType

import java.time.LocalDate
import java.time.DayOfWeek

class WorkshopRegistration {

    String id
    User user
    Branch branch
    LocalDate date
    String orderId
    OrderType orderType
    String receiptId
    BigDecimal amount = BigDecimal.ZERO

    Date dateCreated
    Date lastUpdated
    static constraints = {
        user nullable: false
        branch nullable: false
        orderId nullable: false, unique: true
        orderType nullable: false
        receiptId nullable: false, unique: true

        date validator: { LocalDate val, obj ->
            if (val?.dayOfWeek != DayOfWeek.SUNDAY) {
                return ['workshopRegistration.date.onlySunday']
            }
        }
    }

    static mapping = {
        id generator: 'uuid'
    }
}
