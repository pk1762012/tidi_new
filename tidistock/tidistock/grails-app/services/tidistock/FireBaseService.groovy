package tidistock

import com.google.auth.oauth2.GoogleCredentials
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingException
import com.google.firebase.messaging.Message
import com.google.firebase.messaging.Notification
import grails.gorm.transactions.Transactional
import grails.util.Environment

@Transactional
class FireBaseService {

    void init() {
        if (FirebaseApp.getApps().isEmpty()) {
            InputStream serviceAccount = this.class.classLoader.getResourceAsStream("firebase-key.json")

            FirebaseOptions options = FirebaseOptions.builder()
                    .setCredentials(GoogleCredentials.fromStream(serviceAccount))
                    .build()

            FirebaseApp.initializeApp(options)
        }
    }

    String sendToTopic(String title, String body, String topic = "all") {
        try {
            Notification notification = Notification.builder()
                    .setTitle(title)
                    .setBody(body)
                    .build()

            Message message = Message.builder()
                    .setNotification(notification)
                    .setTopic((Environment.current == Environment.PRODUCTION && topic == "all" ) ? "prod_all" : "test_all")
                    .build()

            return FirebaseMessaging.instance.send(message)
        } catch (FirebaseMessagingException e) {
            e.printStackTrace()
            return "Error: ${e.message}"
        }
    }

    String sendToToken(String token, String title, String body) {
        try {
            Notification notification = Notification.builder()
                    .setTitle(title)
                    .setBody(body)
                    .build()

            Message message = Message.builder()
                    .setToken(token)
                    .setNotification(notification)
                    .build()

            return FirebaseMessaging.instance.send(message)
        } catch (FirebaseMessagingException e) {
            e.printStackTrace()
            return "Error: ${e.message}"
        }
    }
}
