package tidistock.requestbody

import grails.validation.Validateable

class GetBlogCommentPayload implements Validateable{

    Integer limit
    Integer offset
    String blogId

    static constraints = {
        limit nullable: true
        offset nullable: true
        blogId blank: false
    }

}
