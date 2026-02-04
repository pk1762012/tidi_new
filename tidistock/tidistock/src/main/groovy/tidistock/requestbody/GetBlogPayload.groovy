package tidistock.requestbody

import grails.validation.Validateable

import java.time.LocalDate

class GetBlogPayload implements Validateable{
    Integer limit
    Integer offset
    String search
    String sortField
    String sortOrder
    LocalDate blogDate

    static constraints = {
        limit nullable: true
        offset nullable: true
        search nullable: true
        sortField nullable: true
        sortOrder nullable: true
        blogDate nullable: true
    }
}
