package tidistock.requestbody

import grails.validation.Validateable

class NotificationPayload implements Validateable{

    String userId
    String title
    String body

    static constraints = {
        userId nullable: false, blank: false
        title nullable: false, blank: false, maxSize: 65
        body nullable: true, blank: true, maxSize: 180
    }
}
