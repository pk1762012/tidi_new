package tidistock

import tidistock.enums.CourseStatus
import tidistock.enums.OrderType

class CourseOrder {

    String id
    String orderId
    OrderType orderType
    String receiptId
    User user
    Course course
    Branch branch
    CourseStatus status  = CourseStatus.YET_TO_START
    BigDecimal amount = BigDecimal.ZERO

    Date dateCreated
    Date lastUpdated

    static constraints = {
        orderId nullable: false, unique: true
        orderType nullable: false
        receiptId nullable: false, unique: true
        user nullable: false
        course nullable: false
        branch nullable: false
        status nullable: false
    }

    static mapping = {
        id generator: 'uuid'
    }
}
