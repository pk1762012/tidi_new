package tidistock

import grails.core.GrailsApplication
import grails.gorm.transactions.Transactional
import groovy.json.JsonSlurper
import okhttp3.*
import org.springframework.beans.factory.annotation.Autowired
import software.amazon.awssdk.http.HttpStatusCode

@Transactional
class MessageService {

    @Autowired
    GrailsApplication grailsApplication

    def sendOTP(String phoneNumber) {
        String apiUrl = grailsApplication.config.message.api.url
        String authToken = grailsApplication.config.message.api.authToken
        String customerId = grailsApplication.config.message.api.customerId
        OkHttpClient client = new OkHttpClient()
                .newBuilder()
                .build()

        MediaType mediaType = MediaType.parse("text/plain")
        RequestBody body = RequestBody.create(mediaType, "")
        Request request = new Request.Builder()
                .url("${apiUrl}send?countryCode=91&customerId=${customerId}&flowType=SMS&mobileNumber=${phoneNumber}")
                .method("POST", body)
                .addHeader("authToken", authToken)
                .build()

        Response response = client.newCall(request).execute()
        if (response.successful) {
            def jsonSlurper = new JsonSlurper()
            def responseJson = jsonSlurper.parseText(response.body().string())
            response.close()
            return [status : true, verificationId : responseJson?.data?.verificationId]
        } else {
            response.close()
            return [status : false]
        }

    }

    def verifyOTP(String otp, String verificationId) {
        String apiUrl = grailsApplication.config.message.api.url
        String authToken = grailsApplication.config.message.api.authToken

        OkHttpClient client = new OkHttpClient().newBuilder()
                .build();
        Request request = new Request.Builder()
                .url("${apiUrl}validateOtp?verificationId=${verificationId}&code=${otp}")
                .method("GET", null)
                .addHeader("authToken", authToken)
                .build();
        Response response = client.newCall(request).execute()
        def jsonSlurper = new JsonSlurper()
        def responseJson = jsonSlurper.parseText(response.body().string())
        if (responseJson.responseCode == HttpStatusCode.OK) {
            response.close()
            return true
        }
        response.close()
        return false

    }
}
