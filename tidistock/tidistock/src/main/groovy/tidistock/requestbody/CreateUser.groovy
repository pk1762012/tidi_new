package tidistock.requestbody

import grails.validation.Validateable

import java.time.Year

class CreateUser implements Validateable{

    String phone_number

    String firstName

    String lastName




    static constraints = {
        phone_number nullable: false, blank: false, unique: true, matches: /^[0-9]{10}$/
        firstName nullable: false, blank: false, maxSize: 20, minSize: 1
        lastName nullable: true, maxSize: 20
    }

}
