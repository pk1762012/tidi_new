package tidistock

import tidistock.enums.DematEnquiryStatus

class DematEnquiry {

    String id
    String firstName
    String lastName
    String phoneNumber
    Date dateCreated
    Date lastUpdated
    DematEnquiryStatus status = DematEnquiryStatus.ENQUIRED
    String remarks

    static constraints = {
        phoneNumber nullable: false, blank: false, matches: /^[0-9]{10}$/
        firstName nullable: false, blank: false, maxSize: 20, minSize: 1
        lastName nullable: true, maxSize: 20
        status nullable: false
        remarks nullable: true
    }

    static mapping = {
        id generator: 'uuid'
        remarks type: 'text'
    }
}
