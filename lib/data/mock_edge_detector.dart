import 'dart:typed_data';
import 'dart:math';

/// Simulates a local TensorFlow Lite MobileNet inference engine.
/// Runs entirely on-device with zero network calls.
class MockEdgeDetector {
  final Random _random = Random();
  
  String? detectObject(Uint8List cameraBytes) {
    // In a production app, this passes bytes to the TFLite C++ binary.
    // For this prototype, we simulate a lightweight on-device model 
    // evaluating frames until it hits a high-confidence threshold (>95%).
    
    double confidence = _random.nextDouble();
    
    if (confidence > 0.95) {
      const List<String> mockLabels = ["coffee mug", "laptop", "notebook", "houseplant", "keyboard"];
      return mockLabels[_random.nextInt(mockLabels.length)];
    }
    
    // Confidence was too low, return null (meaning: don't wake up the Cloud AI)
    return null;
  }
}




