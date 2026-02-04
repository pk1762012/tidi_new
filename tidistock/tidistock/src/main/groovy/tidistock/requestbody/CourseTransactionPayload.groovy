package tidistock.requestbody

import grails.validation.Validateable
import tidistock.enums.CourseStatus

class CourseTransactionPayload implements Validateable  {
    Integer limit
    Integer offset
    String search
    String sortField
    String sortOrder
    String branchId
    CourseStatus status

    static constraints = {
        limit nullable: true
        offset nullable: true
        search nullable: true
        sortField nullable: true
        sortOrder nullable: true
        branchId nullable: true
        status nullable: true
    }
}
