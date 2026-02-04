package tidistock

class Blog {

    String id
    Date dateCreated
    Date lastUpdated
    String title
    String content

    static hasMany = [comments: BlogComment]

    static constraints = {
        title blank: false, maxSize: 255
        content blank: false, maxSize: 10000
    }

    static mapping = {
        id generator: 'uuid'
        comments cascade: "all-delete-orphan"
    }
}
