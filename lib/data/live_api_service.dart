import 'dart:convert';
import 'dart:typed_data'; // <-- MUST HAVE THIS FOR BINARY DECODING
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class LiveApiService {
  // Put a NEW API key here, and do not push it to GitHub!
  static const String _apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';

  static final Uri _uri = Uri.parse(
      'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=$_apiKey');

  WebSocketChannel? _channel;

  void connect(Function(String) onMessageReceived) {
    _channel = WebSocketChannel.connect(_uri);
    debugPrint("🔌 WebSocket Connection Opened");

    _channel!.stream.listen(
      (message) {
        try {
          // THE FIX: Decode the raw binary audio frames into text before parsing!
          String textMessage;
          if (message is Uint8List || message is List<int>) {
            textMessage = utf8.decode(message as List<int>);
          } else {
            textMessage = message.toString();
          }

          final data = jsonDecode(textMessage);

          if (data['serverContent'] != null) {
            final sc = data['serverContent'];

            // 1. Look for standard text parts
            if (sc['modelTurn'] != null && sc['modelTurn']['parts'] != null) {
              for (var part in sc['modelTurn']['parts']) {
                if (part['text'] != null && part['text'].isNotEmpty) {
                  onMessageReceived(part['text']);
                }
              }
            }
          }
        } catch (e) {
          // Fail silently on weird audio chunks instead of crashing the app
          debugPrint("Stream Parse Error: $e");
        }
      },
      onError: (error) => debugPrint("WebSocket Error: $error"),
      onDone: () => debugPrint(
          "WebSocket Closed. Code: ${_channel!.closeCode}, Reason: ${_channel!.closeReason}"),
    );

    _sendSetupMessage();
  }

  void _sendSetupMessage() {
    final setupMsg = {
      "setup": {
        "model": "models/gemini-2.5-flash-native-audio-preview-12-2025",
        "generationConfig": {
          "responseModalities": ["AUDIO"]
        },
        "outputAudioTranscription": {}
      }
    };
    _channel?.sink.add(jsonEncode(setupMsg));
  }

  void streamCameraFrame(Uint8List imageBytes) {
    if (_channel == null) return;

    final realtimeInputMsg = {
      "realtimeInput": {
        "mediaChunks": [
          {"mimeType": "image/jpeg", "data": base64Encode(imageBytes)}
        ]
      }
    };

    _channel?.sink.add(jsonEncode(realtimeInputMsg));
  }

  void disconnect() {
    _channel?.sink.close();
  }
}
