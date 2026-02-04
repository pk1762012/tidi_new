package tidistock.requestbody

import grails.validation.Validateable

import java.time.Year

class UserDetailsUpdatePayload implements Validateable {

    String firstName
    String lastName

    static constraints = {

        firstName nullable: true, blank: true, maxSize: 20, minSize: 1
        lastName nullable: true, maxSize: 20
    }
}
