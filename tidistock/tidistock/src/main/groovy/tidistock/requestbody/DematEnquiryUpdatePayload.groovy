package tidistock.requestbody

import grails.validation.Validateable
import tidistock.enums.CourseStatus
import tidistock.enums.DematEnquiryStatus

class DematEnquiryUpdatePayload    implements Validateable  {
    String id
    DematEnquiryStatus status
    String remarks
}
