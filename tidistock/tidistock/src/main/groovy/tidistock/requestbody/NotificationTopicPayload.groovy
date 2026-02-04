package tidistock.requestbody

import grails.validation.Validateable

class NotificationTopicPayload implements Validateable{

    String topic
    String title
    String body

    static constraints = {
        topic nullable: false, blank: false
        title nullable: false, blank: false, maxSize: 65
        body nullable: true, blank: true, maxSize: 180
    }
}
