package tidistock.requestbody

import grails.validation.Validateable

class BlogCommentPayload implements Validateable {

    String blogId
    String content

    static constraints = {
        content blank: false, maxSize: 500
        blogId blank: false
    }
}
