import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../data/live_api_service.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const CameraScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  bool _isInitializing = true;
 
  // Instantiate the WebSocket Service
  final LiveApiService _liveService = LiveApiService();
 
  // Timer to automatically stream frames without user interaction
  Timer? _streamingTimer;
 
  // Holds the live transcription text streaming back from the AI
  String _liveTranscription = "Waiting for AI...";

  @override
  void initState() {
    super.initState();
   
    // We use medium resolution to ensure the frames send quickly over WebSockets
    _controller = CameraController(widget.cameras[0], ResolutionPreset.medium);
   
    _controller.initialize().then((_) {
      if (!mounted) return;
     
      setState(() => _isInitializing = false);
     
      // Connect to the Gemini Live WebSocket and listen for text chunks
      _liveService.connect((aiText) {
        if (mounted) {
          setState(() {
            _liveTranscription = aiText;
          });
        }
      });
     
      // Start the automated loop to send frames
      _startStreaming();
     
    }).catchError((e) {
      debugPrint("Camera Error: $e");
    });
  }

  void _startStreaming() {
    // Fire every 2 seconds to act as a continuous visual feed
    _streamingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!_controller.value.isInitialized || _controller.value.isTakingPicture) return;
     
      try {
        // Silently capture a frame
        final image = await _controller.takePicture();
        final bytes = await image.readAsBytes();
       
        // Push the raw bytes down the WebSocket pipe
        _liveService.streamCameraFrame(bytes);
        debugPrint("⬆️ Streamed frame to Gemini");
      } catch (e) {
        debugPrint("Streaming Error: $e");
      }
    });
  }

  @override
  void dispose() {
    // Clean up resources to prevent memory leaks
    _streamingTimer?.cancel();
    _liveService.disconnect();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show a loading screen while the camera hardware turns on
    if (_isInitializing) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white))
      );
    }
   
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. The Continuous Camera Feed
          SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: CameraPreview(_controller)
          ),
         
          // 2. The Professional "LIVE" Indicator (Top Right)
          Positioned(
            top: 60,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.8),
                borderRadius: BorderRadius.circular(20)
              ),
              child: const Row(
                children: [
                  Icon(Icons.fiber_manual_record, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text("LIVE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                ],
              ),
            ),
          ),
         
          // 3. The Live Subtitle Bar (Bottom)
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blueAccent.withOpacity(0.5), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueAccent.withOpacity(0.2),
                    blurRadius: 10,
                    spreadRadius: 2,
                  )
                ]
              ),
              child: Text(
                _liveTranscription,
                style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ),
          )
        ],
      ),
    );
  }
}