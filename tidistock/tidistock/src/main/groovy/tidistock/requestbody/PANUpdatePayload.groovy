package tidistock.requestbody

import grails.validation.Validateable

class PANUpdatePayload implements Validateable{

    String email
    String pan

    static constraints = {
        email nullable: true, email: true
        pan blank: false, nullable: false, validator: { val, obj ->
            val ==~ /^[A-Z]{5}[0-9]{4}[A-Z]$/
        }
    }
}
