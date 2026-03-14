import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import '../data/live_api_service.dart';

class VoiceAgentScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const VoiceAgentScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  State<VoiceAgentScreen> createState() => _VoiceAgentScreenState();
}

class _VoiceAgentScreenState extends State<VoiceAgentScreen> with TickerProviderStateMixin {
  late CameraController _cameraController;
  final LiveApiService _liveService = LiveApiService();
  late stt.SpeechToText _speech;
  Timer? _visualMemoryTimer;
  
  final FlutterTts _flutterTts = FlutterTts();

  bool _isCameraReady = false;
  bool _isListening = false;
  bool _isAiSpeaking = false;
  
  String _userText = "Hold the button, point the camera, and speak...";
  String _aiSubtitle = "";
  String _ttsBuffer = "";
  
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);

    // TTS Setup
    _flutterTts.setLanguage("en-US");
    _flutterTts.setSpeechRate(0.5);
    _flutterTts.setQueueMode(1);

    // Initialize Camera
    _cameraController = CameraController(widget.cameras[0], ResolutionPreset.low);
    _cameraController.initialize().then((_) {
      if (!mounted) return;
      setState(() => _isCameraReady = true);

      // Connect to Gemini
      _liveService.connect((aiTextChunk) {
        if (!mounted) return;
        setState(() {
          if (_aiSubtitle == "Thinking...") _aiSubtitle = "";
          _aiSubtitle += aiTextChunk;
          _isAiSpeaking = true;
        });

        // 💥 Buffered Audio for Zero Stutter
        _ttsBuffer += aiTextChunk;
        if (_ttsBuffer.contains(RegExp(r'[.!?\n]'))) {
          int splitIndex = _ttsBuffer.lastIndexOf(RegExp(r'[.!?\n]')) + 1;
          String sentenceToSpeak = _ttsBuffer.substring(0, splitIndex);
          _flutterTts.speak(sentenceToSpeak);
          _ttsBuffer = _ttsBuffer.substring(splitIndex);
        }
      });

      // 👁️ SCENIC MEMORY: Silently stream what the camera sees every 3 seconds
      _visualMemoryTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
        if (!_cameraController.value.isTakingPicture && !_isListening) {
          final image = await _cameraController.takePicture();
          _liveService.streamVisualMemory(await image.readAsBytes());
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
    
    if (_userText.isNotEmpty && _userText != "Hold the button, point the camera, and speak...") {
      setState(() => _aiSubtitle = "Thinking...");
      
      // Snap a picture at the exact moment you ask a question
      Uint8List? imageBytes;
      if (_cameraController.value.isInitialized) {
        final image = await _cameraController.takePicture();
        imageBytes = await image.readAsBytes();
      }
      
      // Send both Voice and Image together
      _liveService.sendMultimodalPrompt(_userText, imageBytes);
    }
  }

  @override
  void dispose() {
    _visualMemoryTimer?.cancel();
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



