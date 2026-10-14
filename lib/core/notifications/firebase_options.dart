import 'dart:io';

import 'package:firebase_core/firebase_core.dart';

/// Firebase project "Hipersign ERP Push" (from google-services.json). These are public client
/// settings - they ship inside every copy of the app; the secret server key stays on the ERP server.
const _android = FirebaseOptions(
  apiKey: 'AIzaSyDwGhMXG0481wSk0nb3QXVMkdfkc5s85w4',
  appId: '1:728605655341:android:daac945dc1e9d6212bd3a4',
  messagingSenderId: '728605655341',
  projectId: 'ipersign-erp-push',
  storageBucket: 'ipersign-erp-push.firebasestorage.app',
);

/// Options for this platform, or null to use the platform config file (iOS: GoogleService-Info.plist).
FirebaseOptions? get hipersignFirebaseOptions => Platform.isAndroid ? _android : null;
