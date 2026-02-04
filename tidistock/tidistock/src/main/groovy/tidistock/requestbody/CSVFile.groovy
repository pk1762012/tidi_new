package tidistock.requestbody

import grails.validation.Validateable
import org.springframework.web.multipart.MultipartFile

class CSVFile implements Validateable{

    MultipartFile file

    static constraints = {

        file  validator: { val, obj ->
            if ( val == null ) {
                return false
            }
            if ( val.empty ) {
                return false
            }

            ['csv'].any { extension ->
                val.originalFilename?.toLowerCase()?.endsWith(extension)
            }
        }
    }
}
