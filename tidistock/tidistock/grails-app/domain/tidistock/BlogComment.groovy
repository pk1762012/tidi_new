package tidistock

class BlogComment {

    String id
    Date dateCreated
    Date lastUpdated
    Blog blog
    User user
    String content

    static belongsTo = [blog: Blog]

    static constraints = {
        content blank: false, maxSize: 500
        user nullable: false
        blog nullable: false
    }

    static mapping = {
        id generator: 'uuid'
    }
}
