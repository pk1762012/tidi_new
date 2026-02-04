package tidistock.requestbody

import grails.validation.Validateable


class GetUsersPayload implements Validateable {
    Integer limit
    Integer offset
    String search
    String sortField
    String sortOrder

    static constraints = {
        limit nullable: true
        offset nullable: true
        search nullable: true
        sortField nullable: true
        sortOrder nullable: true
    }
}
