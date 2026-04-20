// lib/services/mediapipe_service_mobile.dart
//
// Stub used on Android & iOS. Fully self-contained.

import 'dart:typed_data';

// ========== Data Classes ==========

class HandLandmarks {
  final int handIndex; // 0 = Left, 1 = Right
  final List<Landmark> landmarks;

  const HandLandmarks({
    required this.handIndex,
    required this.landmarks,
  });

  factory HandLandmarks.fromMap(Map<dynamic, dynamic> map) {
    final handIndex = map['handIndex'] as int;
    final landmarksList =
        (map['landmarks'] as List).cast<Map<dynamic, dynamic>>();
    final landmarks = landmarksList
        .map((lm) => Landmark(
              x: (lm['x'] as num).toDouble(),
              y: (lm['y'] as num).toDouble(),
              z: (lm['z'] as num).toDouble(),
            ))
        .toList();
    return HandLandmarks(handIndex: handIndex, landmarks: landmarks);
  }

  @override
  String toString() =>
      'HandLandmarks(handIndex: $handIndex, landmarks: ${landmarks.length})';
}

class Landmark {
  final double x;
  final double y;
  final double z;

  const Landmark({required this.x, required this.y, required this.z});

  @override
  String toString() =>
      'Landmark(x: ${x.toStringAsFixed(4)}, '
      'y: ${y.toStringAsFixed(4)}, '
      'z: ${z.toStringAsFixed(4)})';
}

// ========== MediaPipeService Stub ==========

class MediaPipeService {
  static Future<void> initialize() async {
    throw UnsupportedError(
        'MediaPipeService is only supported on Flutter Web.');
  }

  static Future<List<HandLandmarks>?> detectHands({
    required Uint8List frameBytes,
    required int width,
    required int height,
  }) async {
    throw UnsupportedError(
        'MediaPipeService is only supported on Flutter Web.');
  }

  static Future<void> close() async {
    throw UnsupportedError(
        'MediaPipeService is only supported on Flutter Web.');
  }
}