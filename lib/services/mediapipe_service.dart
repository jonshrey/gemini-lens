import 'dart:typed_data';
import 'package:flutter/services.dart';
export 'mediapipe_service_mobile.dart'
    if (dart.library.js) 'mediapipe_service_web.dart';

class MediaPipeService {
  static const MethodChannel _channel = MethodChannel('mediapipe_channel');

  /// Initializes the native MediaPipe Hand Landmarker.
  static Future<void> initialize() async {
    await _channel.invokeMethod('initializeHandLandmarker');
  }

  /// Processes a JPEG/PNG image frame and returns hand landmarks.
  static Future<List<HandLandmarks>?> detectHands({
    required Uint8List frameBytes,
    required int width,
    required int height,
  }) async {
    final result = await _channel.invokeMethod('detectHands', {
      'bytes': frameBytes,
      'width': width,
      'height': height,
    });
    if (result == null) return null;
    return (result as List)
        .map((hand) => HandLandmarks.fromMap(hand as Map<dynamic, dynamic>))
        .toList();
  }

  static Future<void> close() async {
    await _channel.invokeMethod('close');
  }
}

/// Represents one detected hand with its 21 landmarks.
class HandLandmarks {
  final int handIndex; // 0 = left, 1 = right (approximate)
  final List<Landmark> landmarks;

  HandLandmarks({required this.handIndex, required this.landmarks});

  factory HandLandmarks.fromMap(Map<dynamic, dynamic> map) {
    final handIndex = map['handIndex'] as int;
    final landmarksList = (map['landmarks'] as List).cast<Map<dynamic, dynamic>>();
    final landmarks = landmarksList.map((lm) => Landmark(
          x: (lm['x'] as num).toDouble(),
          y: (lm['y'] as num).toDouble(),
          z: (lm['z'] as num).toDouble(),
        )).toList();
    return HandLandmarks(handIndex: handIndex, landmarks: landmarks);
  }
}

/// A single landmark point with normalized coordinates (0.0 to 1.0).
class Landmark {
  final double x;
  final double y;
  final double z; // depth relative to wrist

  Landmark({required this.x, required this.y, required this.z});
}
