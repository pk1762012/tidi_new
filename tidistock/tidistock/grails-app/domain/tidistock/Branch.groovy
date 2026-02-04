package tidistock

class Branch {

    String id
    String name
    List<String> phoneNumbers
    String mapLink

    String address


    static constraints = {
        name blank: false, maxSize: 50
        address blank: false

    }

    static mapping = {
        id generator: 'uuid'
    }
}
