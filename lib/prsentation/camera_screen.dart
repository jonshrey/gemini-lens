import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import '../data/live_api_service.dart';
import '../data/mock_edge_detector.dart';

class VoiceAgentScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const VoiceAgentScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  State<VoiceAgentScreen> createState() => _VoiceAgentScreenState();
}

class _VoiceAgentScreenState extends State<VoiceAgentScreen> with TickerProviderStateMixin {
  late CameraController _cameraController;
  final LiveApiService _liveService = LiveApiService();
  
  // 1. Initialize our local Edge AI Simulator
  final MockEdgeDetector _edgeDetector = MockEdgeDetector();
  
  late stt.SpeechToText _speech;
  Timer? _edgeInferenceTimer;
  
  final FlutterTts _flutterTts = FlutterTts();

  bool _isCameraReady = false;
  bool _isListening = false;
  bool _isAiSpeaking = false;
  bool _isCloudProcessing = false; // Prevents the Edge AI from spamming the Cloud AI
  
  String _userText = "Hold to speak, or let the Edge AI scan...";
  String _aiSubtitle = "";
  String _ttsBuffer = "";
  
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);

    _flutterTts.setLanguage("en-US");
    _flutterTts.setSpeechRate(0.5);
    _flutterTts.setQueueMode(1);

    _cameraController = CameraController(widget.cameras[0], ResolutionPreset.low);
    _cameraController.initialize().then((_) {
      if (!mounted) return;
      setState(() => _isCameraReady = true);

      _liveService.connect((aiTextChunk) {
        if (!mounted) return;
        setState(() {
          if (_aiSubtitle.startsWith("Edge AI") || _aiSubtitle == "Thinking...") _aiSubtitle = "";
          _aiSubtitle += aiTextChunk;
          _isAiSpeaking = true;
        });

        _ttsBuffer += aiTextChunk;
        if (_ttsBuffer.contains(RegExp(r'[.!?\n]'))) {
          int splitIndex = _ttsBuffer.lastIndexOf(RegExp(r'[.!?\n]')) + 1;
          String sentenceToSpeak = _ttsBuffer.substring(0, splitIndex);
          _flutterTts.speak(sentenceToSpeak);
          _ttsBuffer = _ttsBuffer.substring(splitIndex);
        }
      });

      // 💥 THE HYBRID LOOP: Local Edge Processing
      // We process a frame locally every 500ms (2 FPS)
      _edgeInferenceTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
        // If the Cloud AI is currently talking, or you are holding the mic, pause the Edge AI
        if (_cameraController.value.isTakingPicture || _isListening || _isCloudProcessing) return;
        
        final image = await _cameraController.takePicture();
        final bytes = await image.readAsBytes();
        
        // 1. Run local inference (Zero Latency, Zero Cost)
        String? detectedObject = _edgeDetector.detectObject(bytes);
        
        // 2. If the Edge AI finds something confident, trigger the Cloud Handoff!
        if (detectedObject != null) {
          setState(() {
            _isCloudProcessing = true; // Lock the edge loop
            _aiSubtitle = "Edge AI detected a $detectedObject! Waking up Cloud AI...";
          });
          
          // 3. Send the image to the heavy Gemini Model for deep analysis
          _liveService.sendMultimodalPrompt(
            "My local Edge AI just detected a $detectedObject. Tell me a 1-sentence creative or interesting fact about this object based on what you see.", 
            bytes
          );

          // Unlock the edge loop after 10 seconds so it can scan again
          Future.delayed(const Duration(seconds: 10), () {
            if (mounted) setState(() => _isCloudProcessing = false);
          });
        }
      });
    });
  }

  void _startListening() async {
    if (await _speech.initialize()) {
      setState(() {
        _isListening = true;
        _isAiSpeaking = false;
        _aiSubtitle = "";
        _ttsBuffer = "";
      });
      _speech.listen(onResult: (val) => setState(() => _userText = val.recognizedWords));
    }
  }

  void _stopListening() async {
    setState(() => _isListening = false);
    _speech.stop();
    
    if (_userText.isNotEmpty && _userText != "Hold to speak, or let the Edge AI scan...") {
      setState(() {
        _aiSubtitle = "Thinking...";
        _isCloudProcessing = true; // Pause edge scanning while you ask a manual question
      });
      
      Uint8List? imageBytes;
      if (_cameraController.value.isInitialized) {
        final image = await _cameraController.takePicture();
        imageBytes = await image.readAsBytes();
      }
      
      _liveService.sendMultimodalPrompt(_userText, imageBytes);

      // Resume edge scanning after 10 seconds
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted) setState(() => _isCloudProcessing = false);
      });
    }
  }

  @override
  void dispose() {
    _edgeInferenceTimer?.cancel();
    _pulseController.dispose();
    _liveService.disconnect();
    _flutterTts.stop();
    _cameraController.dispose();
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
          // 1. The Camera Background
          Opacity(
            opacity: 0.5,
            child: SizedBox(width: double.infinity, height: double.infinity, child: CameraPreview(_cameraController)),
          ),

          // 2. The Dark Gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.2), Colors.black.withOpacity(0.9)],
              ),
            ),
          ),

          // 3. The Agent UI
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  
                  // The AI Orb
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Container(
                        height: 150, width: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: _isAiSpeaking ? [Colors.blueAccent, Colors.purpleAccent.withOpacity(0.2)] : [Colors.white24, Colors.transparent],
                          ),
                          boxShadow: _isAiSpeaking 
                              ? [BoxShadow(color: Colors.blueAccent.withOpacity(0.6 * _pulseController.value), blurRadius: 60, spreadRadius: 20)] 
                              : [],
                        ),
                        child: Center(
                          child: Icon(Icons.graphic_eq, size: 60, color: _isAiSpeaking ? Colors.white : Colors.white30),
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Subtitles
                  Container(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: Text(
                        _aiSubtitle.isEmpty ? "I am ready. Show me something." : _aiSubtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w400, height: 1.4, shadows: [Shadow(color: Colors.black, blurRadius: 10)]),
                      ),
                    ),
                  ),

                  const Spacer(),

                  Text(_userText, style: const TextStyle(color: Colors.white54, fontSize: 16)),
                  const SizedBox(height: 20),

                  GestureDetector(
                    onTapDown: (_) => _startListening(),
                    onTapUp: (_) => _stopListening(),
                    child: Container(
                      height: 80, width: 80,
                      decoration: BoxDecoration(color: _isListening ? Colors.white : Colors.white10, shape: BoxShape.circle),
                      child: Icon(Icons.mic, color: _isListening ? Colors.black : Colors.white, size: 36),
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



