package tidistock.requestbody

import tidistock.enums.DeviceType
import grails.validation.Validateable

class DeviceDetails implements Validateable{

    DeviceType deviceType
    String fcmToken

    static constraints = {
        deviceType nullable: false
        fcmToken nullable: false, blank: false, maxSize: 4096
    }
}
