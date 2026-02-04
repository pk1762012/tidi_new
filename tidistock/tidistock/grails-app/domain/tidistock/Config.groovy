package tidistock

class Config {

    String name
    String value

    static constraints = {
        name nullable: false, unique: true
        value nullable: false
    }
}
