package tidistock.requestbody

import grails.validation.Validateable
import org.springframework.web.multipart.MultipartFile

class PANUploadPayload implements Validateable {

    MultipartFile file
    String email
    String pan

    static constraints = {

        file validator: { val, obj ->
            if (!val || val.empty) {
                return false
            }

            ['jpeg', 'jpg', 'png'].any { ext ->
                val.originalFilename?.toLowerCase()?.endsWith(ext)
            }
        }

        email nullable: true, email: true

        pan blank: false, nullable: false, validator: { val, obj ->
            val ==~ /^[A-Z]{5}[0-9]{4}[A-Z]$/
        }
    }
}
