import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return android; // Use android config for windows
      case TargetPlatform.linux:
        return android; // Use android config for linux
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCQbeL63O8-X65UqHQC256oLr0xXJIMQUo',
    appId: '1:29712834204:android:b077a9fc622fe599899759',
    messagingSenderId: '29712834204',
    projectId: 'tidi-4af58',
    storageBucket: 'tidi-4af58.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCQbeL63O8-X65UqHQC256oLr0xXJIMQUo',
    appId: '1:29712834204:android:b077a9fc622fe599899759',
    messagingSenderId: '29712834204',
    projectId: 'tidi-4af58',
    storageBucket: 'tidi-4af58.firebasestorage.app',
    iosBundleId: 'com.tidi.tidistockmobileapp',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCQbeL63O8-X65UqHQC256oLr0xXJIMQUo',
    appId: '1:29712834204:android:b077a9fc622fe599899759',
    messagingSenderId: '29712834204',
    projectId: 'tidi-4af58',
    storageBucket: 'tidi-4af58.firebasestorage.app',
    authDomain: 'tidi-4af58.firebaseapp.com',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCQbeL63O8-X65UqHQC256oLr0xXJIMQUo',
    appId: '1:29712834204:android:b077a9fc622fe599899759',
    messagingSenderId: '29712834204',
    projectId: 'tidi-4af58',
    storageBucket: 'tidi-4af58.firebasestorage.app',
    iosBundleId: 'com.tidi.tidistockmobileapp',
  );
}
