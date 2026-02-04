package tidistock.requestbody

import grails.validation.Validateable

class BlogPayload implements Validateable{

    String title
    String content

    static constraints = {
        title blank: false, maxSize: 255
        content blank: false, maxSize: 10000
    }

}
