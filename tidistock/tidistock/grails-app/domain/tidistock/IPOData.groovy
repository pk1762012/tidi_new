package tidistock

class IPOData {
    String id
    String rawJson
    static constraints = {
        rawJson nullable: false
    }

    static mapping = {
        id generator: 'uuid'
        rawJson type: 'text'
    }
}
