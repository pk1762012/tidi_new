package tidistock

import tidistock.enums.DeviceType
import grails.compiler.GrailsCompileStatic
import groovy.transform.EqualsAndHashCode
import groovy.transform.ToString

import java.time.Year

@GrailsCompileStatic
@EqualsAndHashCode(includes= ['username'])
@ToString(includes='username', includeNames=true, includePackage=false)
class User implements Serializable {

    private static final long serialVersionUID = 1

    String id
    String firstName
    String lastName
    String username
    String password
    boolean enabled = true
    boolean accountExpired
    boolean accountLocked
    boolean passwordExpired
    Date dateCreated
    Date lastUpdated
    String verificationId
    Wallet wallet
    String profilePictureFile
    String fcmToken
    DeviceType deviceType
    String email
    String pan

    Set<Role> getAuthorities() {
        (UserRole.findAllByUser(this) as List<UserRole>)*.role as Set<Role>
    }

    static constraints = {
        password nullable: false, blank: false, password: true, validator: { val, obj ->
            (val as String)?.matches(/^(?=.*[A-Z])(?=.*[@#$%^&+=])(?=.*[a-zA-Z0-9]).{8,}$/)  // Explicitly cast to String and validate
        }
        username nullable: false, blank: false, unique: true, matches: /^[0-9]{10}$/
        verificationId nullable: true
        wallet nullable: false, unique: true
        profilePictureFile nullable: true
        firstName nullable: false, blank: false, maxSize: 20, minSize: 1
        lastName nullable: true, maxSize: 20
        fcmToken nullable: true, maxSize: 4096
        deviceType nullable: true
        email nullable: true, email: true

        pan nullable: true, validator: { val, obj ->
            (val as String)?.matches(/^[A-Z]{5}[0-9]{4}[A-Z]$/)
        }
    }

    static mapping = {
	    password column: '`password`'
        id generator: 'uuid'
    }
}
