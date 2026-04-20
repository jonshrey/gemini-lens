// lib/services/mediapipe_service_web.dart
//
// ⚠️ Never import this directly — always use mediapipe_service.dart
//
// This file uses dart:js_util and package:js which are web-only.
// The linter warning is suppressed intentionally — this file is
// only ever compiled on Flutter Web via the conditional export.
//
// Also add this to analysis_options.yaml to suppress project-wide:
//   analyzer:
//     errors:
//       avoid_web_libraries_in_flutter: ignore

// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
// ignore: uri_does_not_exist
import 'dart:js_util' as js_util;
import 'dart:typed_data';

// ignore: uri_does_not_exist
import 'package:js/js.dart' as js;

// ========== JS Interop ==========

@js.JS('FilesetResolver')
class _FilesetResolver {
  external static dynamic forVisionTasks(String wasmPath);
}

@js.JS('HandLandmarker')
class _HandLandmarker {
  external static dynamic createFromOptions(dynamic vision, dynamic options);
  external dynamic detect(dynamic image);
  external void close();
}

@js.JS('Blob')
external dynamic get _blobConstructor;

@js.JS('createImageBitmap')
external dynamic _createImageBitmap(dynamic source);

// ========== Data Classes ==========

class HandLandmarks {
  final int handIndex;
  final List<Landmark> landmarks;

  const HandLandmarks({required this.handIndex, required this.landmarks});

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
  String toString() => 'Landmark(x: ${x.toStringAsFixed(4)}, '
      'y: ${y.toStringAsFixed(4)}, z: ${z.toStringAsFixed(4)})';
}

// ========== MediaPipeService ==========

class MediaPipeService {
  static dynamic _handLandmarker;
  static bool _isInitialized = false;
  static bool _isInitializing = false;
  static Completer<void>? _initCompleter;

  static Future<void> initialize() async {
    if (_isInitialized) return;
    if (_isInitializing) {
      await _initCompleter?.future;
      return;
    }

    _isInitializing = true;
    _initCompleter = Completer<void>();

    try {
      // 1. Load WASM runtime
      final vision = await js_util.promiseToFuture<dynamic>(
        _FilesetResolver.forVisionTasks(
          'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm',
        ),
      );

      // 2. Build options
      final options = js_util.jsify({
        'baseOptions': {
          'modelAssetPath': 'assets/models/hand_landmarker.task',
          'delegate': 'GPU',
        },
        'runningMode': 'IMAGE',
        'numHands': 2,
      });

      // 3. Create HandLandmarker
      _handLandmarker = await js_util.promiseToFuture<dynamic>(
        _HandLandmarker.createFromOptions(vision, options),
      );

      _isInitialized = true;
      _initCompleter!.complete();
    } catch (e) {
      _initCompleter!.completeError(e);
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  static Future<List<HandLandmarks>?> detectHands({
    required Uint8List frameBytes,
    required int width,
    required int height,
  }) async {
    if (!_isInitialized || _handLandmarker == null) {
      throw StateError(
          'MediaPipeService not initialized. Call initialize() first.');
    }

    try {
      final blob = _bytesToBlob(frameBytes);
      final imageBitmap = await js_util.promiseToFuture<dynamic>(
        _createImageBitmap(blob),
      );

      final result = js_util.callMethod<dynamic>(
          _handLandmarker, 'detect', [imageBitmap]);

      final landmarksList =
          js_util.getProperty<List<dynamic>>(result, 'landmarks');
      final handednessList =
          js_util.getProperty<List<dynamic>>(result, 'handedness');

      final hands = <HandLandmarks>[];

      for (int i = 0; i < landmarksList.length; i++) {
        final rawLandmarks = landmarksList[i] as List<dynamic>;

        final landmarks = rawLandmarks.map((lm) {
          return Landmark(
            x: (js_util.getProperty<num>(lm, 'x')).toDouble(),
            y: (js_util.getProperty<num>(lm, 'y')).toDouble(),
            z: (js_util.getProperty<num>(lm, 'z')).toDouble(),
          );
        }).toList();

        int handIndex = i;
        if (handednessList.isNotEmpty && i < handednessList.length) {
          final categories = handednessList[i] as List<dynamic>;
          if (categories.isNotEmpty) {
            final categoryName =
                js_util.getProperty<String?>(categories.first, 'categoryName');
            handIndex = (categoryName == 'Left') ? 0 : 1;
          }
        }

        hands.add(HandLandmarks(handIndex: handIndex, landmarks: landmarks));
      }

      return hands;
    } catch (e) {
      // ignore: avoid_print
      print('MediaPipe detection error: $e');
      return null;
    }
  }

  static Future<void> close() async {
    if (_handLandmarker != null) {
      js_util.callMethod<void>(_handLandmarker, 'close', []);
      _handLandmarker = null;
    }
    _isInitialized = false;
    _isInitializing = false;
    _initCompleter = null;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static dynamic _bytesToBlob(Uint8List bytes) {
    final jsBytes = js_util.jsify(bytes.buffer.asUint8List());
    final parts = js_util.jsify([jsBytes]);
    final opts = js_util.jsify({'type': 'image/jpeg'});
    return js_util.callConstructor<dynamic>(_blobConstructor, [parts, opts]);
  }
}