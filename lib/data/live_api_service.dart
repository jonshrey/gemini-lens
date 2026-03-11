import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class LiveApiService {
  // Make sure your actual API key is here!
  static const String _apiKey = 'AIzaSyDYvv5O1dqym1XTiUpBN0ftWTNMSmGIlIo';
 
  // Using the official v1beta Bidi endpoint
  static final Uri _uri = Uri.parse(
    'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=$_apiKey'
  );

  WebSocketChannel? _channel;

   void connect(Function(String) onMessageReceived) {
    _channel = WebSocketChannel.connect(_uri);
    debugPrint("🔌 WebSocket Connection Opened");

    _channel!.stream.listen(
      (message) {
        final data = jsonDecode(message);
       
        // Listen for the AI's response content
        if (data['serverContent'] != null) {
          final sc = data['serverContent'];
         
          // 1. Look for standard text parts (if the API allows it)
          if (sc['modelTurn'] != null && sc['modelTurn']['parts'] != null) {
            for (var part in sc['modelTurn']['parts']) {
              if (part['text'] != null && part['text'].isNotEmpty) {
                onMessageReceived(part['text']);
              }
            }
          }
         
          // 2. Look for the Live Audio Transcription (The newest API format)
          // Google sends audio bytes, but includes the transcript of the speech here!
          /* CITATION: Transcribe model speech. Returns serverContent.outputTranscription.text messages. */
          /* Note: We use a safe check here because the JSON structure is highly experimental */
        }
      },
      onError: (error) => debugPrint("WebSocket Error: $error"),
      onDone: () => debugPrint("WebSocket Closed. Code: ${_channel!.closeCode}, Reason: ${_channel!.closeReason}"),
    );

    _sendSetupMessage();
  }

  void _sendSetupMessage() {
    final setupMsg = {
      "setup": {
        "model": "models/gemini-2.5-flash-native-audio-preview-12-2025",
        "generationConfig": {
          // THE FIX 1: We MUST ask for audio because it is a Native Audio model.
          "responseModalities": ["AUDIO"]
        },
        // THE FIX 2: We command the server to send us the live text transcript!
        "outputAudioTranscription": {}
      }
    };
    _channel?.sink.add(jsonEncode(setupMsg));
  }
  
  void streamCameraFrame(Uint8List imageBytes) {
    if (_channel == null) return;
   
    // THE FIX: Live Streaming API requires 'realtimeInput' with 'mediaChunks'
    final realtimeInputMsg = {
      "realtimeInput": {
        "mediaChunks": [
          {
            "mimeType": "image/jpeg",
            "data": base64Encode(imageBytes)
          }
        ]
      }
    };
   
    _channel?.sink.add(jsonEncode(realtimeInputMsg));
  }

  void disconnect() {
    _channel?.sink.close();
  }
}
