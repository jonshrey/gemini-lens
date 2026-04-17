import 'dart:async';
import 'dart:typed_data';
import 'package:js/js.dart' as js;
import 'package:js/js_util.dart' as js_util;

/// JavaScript interop for MediaPipe Tasks Vision
@js.JS('FilesetResolver')
class FilesetResolver {
  external static dynamic forVisionTasks(String wasmPath);
}

@js.JS('HandLandmarker')
class HandLandmarker {
  external static dynamic createFromOptions(dynamic vision, dynamic options);
  external dynamic detect(dynamic image);
  external void close();
}

/// Service that wraps MediaPipe Hand Landmarker for Flutter web.
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
      // 1. Load Vision WASM runtime
      final visionPromise = FilesetResolver.forVisionTasks(
        'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm',
      );
      final vision = await js_util.promiseToFuture(visionPromise);

      // 2. Create HandLandmarker
      final options = js_util.jsify({
        'baseOptions': {
          'modelAssetPath': 'assets/models/hand_landmarker.task',
          'delegate': 'GPU',
        },
        'runningMode': 'IMAGE',
        'numHands': 2,
      });

      final handLandmarkerPromise = HandLandmarker.createFromOptions(vision, options);
      _handLandmarker = await js_util.promiseToFuture(handLandmarkerPromise);
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
    if (_handLandmarker == null) {
      throw StateError('MediaPipeService not initialized. Call initialize() first.');
    }

    try {
      // Create an ImageBitmap from bytes
      final blob = await _bytesToBlob(frameBytes);
      final imageBitmap = await _blobToImageBitmap(blob);

      // Run inference
      final result = js_util.callMethod(_handLandmarker, 'detect', [imageBitmap]);

      // Parse landmarks
      final landmarksList = js_util.getProperty(result, 'landmarks') as List<dynamic>;
      final handednessList = js_util.getProperty(result, 'handedness') as List<dynamic>;

      final hands = <HandLandmarks>[];
      for (int i = 0; i < landmarksList.length; i++) {
        final rawLandmarks = landmarksList[i] as List<dynamic>;
        final landmarks = rawLandmarks.map((lm) {
          return Landmark(
            x: (js_util.getProperty(lm, 'x') as num).toDouble(),
            y: (js_util.getProperty(lm, 'y') as num).toDouble(),
            z: (js_util.getProperty(lm, 'z') as num).toDouble(),
          );
        }).toList();

        int handIndex = i;
        if (handednessList.isNotEmpty && handednessList[i] != null) {
          final categories = handednessList[i] as List<dynamic>;
          if (categories.isNotEmpty) {
            final category = categories.first;
            final categoryName = js_util.getProperty(category, 'categoryName') as String?;
            handIndex = categoryName == 'Left' ? 0 : 1;
          }
        }

        hands.add(HandLandmarks(handIndex: handIndex, landmarks: landmarks));
      }

      return hands;
    } catch (e) {
      print('MediaPipe detection error: $e');
      return null;
    }
  }

  static Future<dynamic> _bytesToBlob(Uint8List bytes) async {
    final jsArray = js_util.jsify(bytes);
    final blob = js_util.callConstructor(
      js_util.getProperty(js_util.globalThis, 'Blob'),
      [jsArray, js_util.jsify({'type': 'image/jpeg'})],
    );
    return blob;
  }

  static Future<dynamic> _blobToImageBitmap(dynamic blob) async {
    final createImageBitmap = js_util.getProperty(js_util.globalThis, 'createImageBitmap');
    final promise = js_util.callMethod(createImageBitmap, 'call', [null, blob]);
    return js_util.promiseToFuture(promise);
  }

  static Future<void> close() async {
    if (_handLandmarker != null) {
      js_util.callMethod(_handLandmarker, 'close', []);
      _handLandmarker = null;
    }
    _isInitialized = false;
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