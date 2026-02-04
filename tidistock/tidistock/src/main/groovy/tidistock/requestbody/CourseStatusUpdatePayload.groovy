package tidistock.requestbody

import grails.validation.Validateable
import tidistock.enums.CourseStatus

class CourseStatusUpdatePayload  implements Validateable  {
    String id
    CourseStatus status

    static constraints = {
        id nullable: false
        status nullable: false
    }
}
