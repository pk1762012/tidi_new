package tidistock.requestbody

import grails.validation.Validateable
import org.springframework.web.multipart.MultipartFile

class ProfilePicture implements Validateable{

    MultipartFile file

    static constraints = {

        file  validator: { val, obj ->
            if ( val == null ) {
                return false
            }
            if ( val.empty ) {
                return false
            }

            ['jpeg', 'jpg', 'png'].any { extension ->
                val.originalFilename?.toLowerCase()?.endsWith(extension)
            }
        }
    }
}
