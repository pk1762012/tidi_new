package tidistock.requestbody

import grails.validation.Validateable

class DematEnquiryPayload  implements Validateable  {

    String firstName
    String lastName
    String phoneNumber

    static constraints = {
        phoneNumber nullable: false, blank: false, matches: /^[0-9]{10}$/
        firstName nullable: false, blank: false, maxSize: 20, minSize: 1
        lastName nullable: true, maxSize: 20
    }
}
