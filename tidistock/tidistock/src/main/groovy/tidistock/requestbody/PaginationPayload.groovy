package tidistock.requestbody


import grails.validation.Validateable

class PaginationPayload implements Validateable {

    Integer limit
    Integer offset

    static constraints = {
        limit nullable: true
        offset nullable: true
    }
}
