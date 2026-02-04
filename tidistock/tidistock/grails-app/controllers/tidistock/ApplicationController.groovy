package tidistock

import grails.core.GrailsApplication
import grails.plugins.GrailsPluginManager
import grails.plugins.PluginManagerAware
import org.springframework.security.access.annotation.Secured

class ApplicationController implements PluginManagerAware {

    GrailsApplication grailsApplication
    GrailsPluginManager pluginManager
    CallJobService callJobService
    def fireBaseService

    @Secured('permitAll')
    def index() {
        //callJobService.getFIIDIIData()
        //println(params)
        //callJobService.getIPOData()
        //callJobService.fetchOpeningPrice("https://www.moneycontrol.com/indian-indices/nifty-50-9.html")
        /*com.razorpay.Utils.verifyWebhookSignature(request.JSON, request.getHeader("x-razorpay-signature"), "tester")*/
        //fireBaseService.sendToTopic("test", "test message")
        //fireBaseService.sendToToken("e9QZUB4ZYEFcsqO0B_5F4o:APA91bFr7mTmkdul-TRHhsFPA9R0CsF3K8ujjFw5JcUECl_mmdunnn-Wb1y1vmOvVhvbpyxbIP18mj7q4OIeH4qMRp-F8qb8rYjLuIQXyiuN7dWOY9wFZyE", "test", "test")
        [grailsApplication: grailsApplication, pluginManager: pluginManager]
    }
}
