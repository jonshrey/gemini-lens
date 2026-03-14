import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class LiveApiService {
  static final String _apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';

  static final Uri _uri = Uri.parse(
      'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=$_apiKey');

  WebSocketChannel? _channel;

  // 💥 THE FIX: Exactly ONE argument expected here!
  void connect(Function(String) onMessageReceived) {
    _channel = WebSocketChannel.connect(_uri);
    debugPrint("🔌 WebSocket Connection Opened");

    _channel!.stream.listen(
      (message) {
        try {
          String textMessage;
          if (message is Uint8List || message is List<int>) {
            textMessage = utf8.decode(message as List<int>);
          } else {
            textMessage = message.toString();
          }

          final data = jsonDecode(textMessage);

          if (data['serverContent'] != null) {
            final sc = data['serverContent'];

            if (sc['outputTranscription'] != null) {
              final transcriptText = sc['outputTranscription']['text'];
              if (transcriptText != null && transcriptText.isNotEmpty) {
                onMessageReceived(transcriptText);
              }
            }
          }
        } catch (e) {
          debugPrint("Stream Parse Error: $e");
        }
      },
      onError: (error) => debugPrint("WebSocket Error: $error"),
      onDone: () =>
          debugPrint("WebSocket Closed. Code: ${_channel!.closeCode}"),
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
        "outputAudioTranscription": {},
        "systemInstruction": {
          "parts": [
            {
              "text":
                  "You are a concise, direct AI voice assistant. Answer directly in 1 short sentence. NEVER narrate your visual analysis."
            }
          ]
        }
      }
    };
    _channel?.sink.add(jsonEncode(setupMsg));
  }

  // BUILD SCENIC MEMORY
  void streamVisualMemory(Uint8List imageBytes) {
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

  // TRIGGER ACTION
  void sendMultimodalPrompt(String spokenText, Uint8List? imageBytes) {
    if (_channel == null || spokenText.isEmpty) return;

    List<Map<String, dynamic>> promptParts = [
      {"text": spokenText}
    ];

    if (imageBytes != null) {
      promptParts.add({
        "inlineData": {
          "mimeType": "image/jpeg",
          "data": base64Encode(imageBytes)
        }
      });
    }

    final clientContent = {
      "clientContent": {
        "turns": [
          {"role": "user", "parts": promptParts}
        ],
        "turnComplete": true
      }
    };

    _channel?.sink.add(jsonEncode(clientContent));
    debugPrint(
        "🗣️ Sent Multimodal Prompt (with Image: ${imageBytes != null})");
  }

  void disconnect() {
    _channel?.sink.close();
  }
}
