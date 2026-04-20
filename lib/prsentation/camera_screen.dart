import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import '../data/live_api_service.dart';
import '../services/mediapipe_service.dart';
import '../utils/gesture_utils.dart';

class VoiceAgentScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const VoiceAgentScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  State<VoiceAgentScreen> createState() => _VoiceAgentScreenState();
}

class _VoiceAgentScreenState extends State<VoiceAgentScreen>
    with TickerProviderStateMixin {
  late CameraController _cameraController;
  final LiveApiService _liveService = LiveApiService();

  late stt.SpeechToText _speech;
  Timer? _edgeInferenceTimer;

  final FlutterTts _flutterTts = FlutterTts();

  bool _isCameraReady = false;
  bool _isListening = false;
  bool _isAiSpeaking = false;
  bool _isCloudProcessing = false;
  bool _mediaPipeReady = false;

  // Buffering the entire response from the AI
  String _fullResponseBuffer = '';
  Timer? _streamEndTimer;
  bool _isStreaming = false;

  String _userText = "Hold to speak, or point at something...";
  String _aiSubtitle = "";
  String _lastDetectedGesture = "";

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);

    _flutterTts.setLanguage("en-US");
    _flutterTts.setSpeechRate(0.5);
    _flutterTts.setQueueMode(1);

    _cameraController =
        CameraController(widget.cameras[0], ResolutionPreset.low);
    _cameraController.initialize().then((_) async {
      if (!mounted) return;
      setState(() => _isCameraReady = true);

      try {
        await MediaPipeService.initialize();
        if (mounted) setState(() => _mediaPipeReady = true);
      } catch (e) {
        debugPrint("MediaPipe initialization failed: $e");
      }

      // Connect to the live AI stream – buffer everything
      await _liveService.connect((aiTextChunk) {
        if (!mounted) return;

        // Reset the end-of-stream timer on each new chunk
        _streamEndTimer?.cancel();
        _streamEndTimer = Timer(const Duration(milliseconds: 500), _finalizeResponse);

        if (!_isStreaming) {
          setState(() {
            _isStreaming = true;
            _isCloudProcessing = true;
            _aiSubtitle = "Thinking...";
          });
        }

        // Accumulate raw chunks (including any reasoning)
        _fullResponseBuffer += aiTextChunk;
      });

      _edgeInferenceTimer =
          Timer.periodic(const Duration(milliseconds: 500), (_) async {
        if (_cameraController.value.isTakingPicture ||
            _isListening ||
            _isCloudProcessing) return;
        if (!_mediaPipeReady) return;

        final image = await _cameraController.takePicture();
        final bytes = await image.readAsBytes();
        final previewSize = _cameraController.value.previewSize!;

        final hands = await MediaPipeService.detectHands(
          frameBytes: bytes,
          width: previewSize.width.toInt(),
          height: previewSize.height.toInt(),
        );

        String? detectedGesture;
        if (hands != null && hands.isNotEmpty) {
          final hand = hands.first;
          detectedGesture = GestureUtils.describeGesture(hand);
          setState(() => _lastDetectedGesture = detectedGesture!);
        } else {
          setState(() => _lastDetectedGesture = "");
        }

        if (detectedGesture == "pointing") {
          setState(() {
            _isCloudProcessing = true;
            _aiSubtitle = "You're pointing! Asking Gemini...";
          });

          final enhancedPrompt =
              _buildEnhancedPrompt("What am I pointing at?", detectedGesture!);
          _liveService.sendMultimodalPrompt(enhancedPrompt, bytes);

          Future.delayed(const Duration(seconds: 8), () {
            if (mounted) setState(() => _isCloudProcessing = false);
          });
        }
      });
    });
  }

  // Called when the AI stream ends (no new chunks for 500ms)
  void _finalizeResponse() {
    if (!mounted) return;

    // Extract the final answer by removing all reasoning content
    final finalAnswer = _extractFinalAnswer(_fullResponseBuffer);

    setState(() {
      _isStreaming = false;
      _isCloudProcessing = false;
      _aiSubtitle = finalAnswer;
    });

    // Speak only the final, cleaned answer
    if (finalAnswer.isNotEmpty) {
      _flutterTts.speak(finalAnswer);
      setState(() => _isAiSpeaking = true);
      _flutterTts.setCompletionHandler(() {
        if (mounted) setState(() => _isAiSpeaking = false);
      });
    }

    // Reset buffer for next interaction
    _fullResponseBuffer = '';
    _streamEndTimer = null;
  }

  // Enhanced reasoning filter – removes all common thinking patterns
  String _extractFinalAnswer(String raw) {
    if (raw.isEmpty) return "I'm not sure how to answer that.";

    // 1. Remove XML-like tags
    String cleaned = raw.replaceAll(RegExp(r'<thinking>[\s\S]*?</thinking>', dotAll: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'\[THOUGHT\][\s\S]*?\[/THOUGHT\]', dotAll: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'\{.*?\}'), ''); // remove JSON-like blocks

    // 2. Remove markdown italics and bold (often used for reasoning)
    cleaned = cleaned.replaceAll(RegExp(r'\*[^*]*\*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'_[^_]*_'), '');

    // 3. Remove common reasoning prefixes (case-insensitive, at start of string or after newline)
    final reasoningPrefixes = [
      r'^I see\b.*?\.\s*',
      r'^I think\b.*?\.\s*',
      r'^Let me\b.*?\.\s*',
      r'^First,?\b.*?\.\s*',
      r'^Based on (the )?image\b.*?\.\s*',
      r'^The image shows\b.*?\.\s*',
      r'^After analyzing\b.*?\.\s*',
      r'^My analysis\b.*?\.\s*',
      r'^Here is my reasoning\b.*?\.\s*',
      r'^As an AI\b.*?\.\s*',
    ];
    for (final prefix in reasoningPrefixes) {
      cleaned = cleaned.replaceFirst(RegExp(prefix, caseSensitive: false, dotAll: true), '');
    }

    // 4. If the text contains multiple sentences separated by periods, keep only the last one
    //    (reasoning often appears before the final answer)
    final sentences = cleaned.split(RegExp(r'(?<=[.!?])\s+'));
    if (sentences.length > 1) {
      // Heuristic: final answer is usually the last sentence
      cleaned = sentences.last.trim();
    }

    // 5. Remove any leftover phrases like "I see", "I think" etc. anywhere in the text
    cleaned = cleaned.replaceAll(RegExp(r'\b(I see|I think|Let me|First,?|Based on|The image shows|After analyzing|My analysis|Here is my reasoning)\b', caseSensitive: false), '');

    // 6. Trim and clean up extra whitespace
    cleaned = cleaned.trim();
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');

    if (cleaned.isEmpty) {
      return "I'm not sure how to answer that.";
    }
    return cleaned;
  }

  // ----------------------------------------------------------------------
  // Speech and UI helpers
  // ----------------------------------------------------------------------

  void _startListening() async {
    if (await _speech.initialize()) {
      setState(() {
        _isListening = true;
        _isAiSpeaking = false;
        _aiSubtitle = "";
        _fullResponseBuffer = "";
        _isStreaming = false;
        _streamEndTimer?.cancel();
      });
      _speech.listen(
          onResult: (val) => setState(() => _userText = val.recognizedWords));
    }
  }

  void _stopListening() async {
    setState(() => _isListening = false);
    _speech.stop();

    if (_userText.isNotEmpty &&
        _userText != "Hold to speak, or point at something...") {
      setState(() {
        _aiSubtitle = "Thinking...";
        _isCloudProcessing = true;
      });

      Uint8List? imageBytes;
      if (_cameraController.value.isInitialized) {
        final image = await _cameraController.takePicture();
        imageBytes = await image.readAsBytes();
      }

      final enhancedPrompt =
          _buildEnhancedPrompt(_userText, _lastDetectedGesture);
      _liveService.sendMultimodalPrompt(enhancedPrompt, imageBytes);
    }
  }

  String _buildEnhancedPrompt(String userQuery, String detectedGesture) {
    if (detectedGesture.isEmpty) return userQuery;
    return '''
The user asked: "$userQuery"

[On-device vision context]
The camera currently detects a hand making a "$detectedGesture" gesture.

Please respond naturally:
- Answer the user's question.
- Mention the detected gesture if it is relevant to the scene.
- Describe what you see in the image, including the person, clothing, and the hand gesture.

Keep your response short and conversational (1–2 sentences).
''';
  }

  @override
  void dispose() {
    _edgeInferenceTimer?.cancel();
    _streamEndTimer?.cancel();
    _pulseController.dispose();
    _liveService.disconnect();
    _flutterTts.stop();
    _cameraController.dispose();
    MediaPipeService.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraReady) return const Scaffold(backgroundColor: Colors.black);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: 0.5,
            child: SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: CameraPreview(_cameraController),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.2),
                  Colors.black.withOpacity(0.9)
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Container(
                        height: 150,
                        width: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: _isAiSpeaking
                                ? [
                                    Colors.blueAccent,
                                    Colors.purpleAccent.withOpacity(0.2)
                                  ]
                                : [Colors.white24, Colors.transparent],
                          ),
                          boxShadow: _isAiSpeaking
                              ? [
                                  BoxShadow(
                                    color: Colors.blueAccent.withOpacity(
                                        0.6 * _pulseController.value),
                                    blurRadius: 60,
                                    spreadRadius: 20,
                                  )
                                ]
                              : [],
                        ),
                        child: Center(
                          child: Icon(
                            Icons.graphic_eq,
                            size: 60,
                            color:
                                _isAiSpeaking ? Colors.white : Colors.white30,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 40),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: Text(
                        _aiSubtitle.isEmpty
                            ? (_lastDetectedGesture.isNotEmpty
                                ? "Gesture: $_lastDetectedGesture"
                                : "I am ready. Point at something or speak.")
                            : _aiSubtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w400,
                          height: 1.4,
                          shadows: [
                            Shadow(color: Colors.black, blurRadius: 10)
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _userText,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTapDown: (_) => _startListening(),
                    onTapUp: (_) => _stopListening(),
                    child: Container(
                      height: 80,
                      width: 80,
                      decoration: BoxDecoration(
                        color: _isListening ? Colors.white : Colors.white10,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.mic,
                        color: _isListening ? Colors.black : Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}