package tidistock.requestbody

import grails.validation.Validateable

class ResetPassword  implements Validateable{

    String phone_number;

    String new_password;

    String otp;

    static constraints = {
        new_password nullable: false, blank: false, password: true, validator: { val, obj ->
            (val as String)?.matches(/^(?=.*[A-Z])(?=.*[@#$%^&+=])(?=.*[a-zA-Z0-9]).{8,}$/)  // Explicitly cast to String and validate
        }
        phone_number nullable: false, blank: false, unique: true, matches: /^[0-9]{10}$/
        otp nullable: false, blank: false, unique: true, matches: /^[0-9]{4}$/
    }

}
