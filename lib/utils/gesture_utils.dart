import '../services/mediapipe_service.dart';

class GestureUtils {
  // Landmark indices for hand (MediaPipe Hand Landmarker model)
  static const int wrist = 0;
  static const int thumbTip = 4;
  static const int indexFingerTip = 8;
  static const int indexFingerDip = 6;  // lower joint
  static const int middleFingerTip = 12;
  static const int ringFingerTip = 16;
  static const int pinkyTip = 20;

  /// Checks if the user is pointing with their index finger.
  /// Pointing is defined as: index tip is higher (smaller y) than its dip,
  /// and all other fingers are curled (tips below their respective dips).
  static bool isPointingGesture(HandLandmarks hand) {
    final landmarks = hand.landmarks;
    
    // Index finger extended?
    bool indexExtended = landmarks[indexFingerTip].y < landmarks[indexFingerDip].y;
    
    // Other fingers curled?
    bool middleCurled = landmarks[middleFingerTip].y > landmarks[6].y; // using index dip as rough reference
    bool ringCurled = landmarks[ringFingerTip].y > landmarks[6].y;
    bool pinkyCurled = landmarks[pinkyTip].y > landmarks[6].y;
    bool thumbCurled = landmarks[thumbTip].x > landmarks[2].x; // thumb heuristic
    
    return indexExtended && middleCurled && ringCurled && pinkyCurled && thumbCurled;
  }

  /// Checks if the user is showing a thumbs-up.
  /// Thumb tip is above the wrist and other fingers are curled.
  static bool isThumbsUpGesture(HandLandmarks hand) {
    final landmarks = hand.landmarks;
    bool thumbUp = landmarks[thumbTip].y < landmarks[wrist].y;
    bool fingersCurled = landmarks[indexFingerTip].y > landmarks[wrist].y &&
                         landmarks[middleFingerTip].y > landmarks[wrist].y;
    return thumbUp && fingersCurled;
  }

  /// Returns a human-readable description of the gesture.
  static String describeGesture(HandLandmarks hand) {
    if (isPointingGesture(hand)) return "pointing";
    if (isThumbsUpGesture(hand)) return "thumbs up";
    return "hand detected";
  }
}