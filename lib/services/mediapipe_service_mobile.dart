import 'dart:typed_data';
import 'package:flutter/services.dart';

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

// ========== Data Classes ==========

class HandLandmarks {
  final int handIndex;
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

class Landmark {
  final double x, y, z;
  Landmark({required this.x, required this.y, required this.z});
}