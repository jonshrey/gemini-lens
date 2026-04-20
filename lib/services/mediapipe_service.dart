// lib/services/mediapipe_service.dart
//
// ✅ Import ONLY this file anywhere in your app.
// dart.library.html is available on web with js ^0.6.x

export 'mediapipe_service_mobile.dart'
    if (dart.library.html) 'mediapipe_service_web.dart';