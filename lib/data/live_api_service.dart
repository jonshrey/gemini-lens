import 'dart:async';
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

  // Connection state
  bool _isConnected = false;
  bool _isSetupComplete = false;
  bool _isConnecting = false;

  // Holds the completer that resolves when setup is fully acknowledged
  Completer<void>? _setupCompleter;

  // Callback saved so reconnect can re-register it
  Function(String)? _onMessageReceived;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Call this once. Awaiting it guarantees the socket is open AND
  /// the server has acknowledged setup before returning.
  Future<void> connect(Function(String) onMessageReceived) async {
    if (_isConnecting || _isConnected) return;

    _onMessageReceived = onMessageReceived;
    await _connectInternal();
  }

  bool get isConnected => _isConnected && _isSetupComplete;

  /// Send a camera frame as visual context.
  Future<void> streamVisualMemory(Uint8List imageBytes) async {
    await _ensureReady();
    _send(jsonEncode({
      "realtimeInput": {
        "mediaChunks": [
          {"mimeType": "image/jpeg", "data": base64Encode(imageBytes)}
        ]
      }
    }));
  }

  /// Send spoken text + optional image as a multimodal prompt.
  Future<void> sendMultimodalPrompt(
      String spokenText, Uint8List? imageBytes) async {
    if (spokenText.isEmpty) return;
    await _ensureReady();

    final List<Map<String, dynamic>> parts = [
      {"text": spokenText}
    ];
    if (imageBytes != null) {
      parts.add({
        "inlineData": {
          "mimeType": "image/jpeg",
          "data": base64Encode(imageBytes)
        }
      });
    }

    _send(jsonEncode({
      "clientContent": {
        "turns": [
          {"role": "user", "parts": parts}
        ],
        "turnComplete": true
      }
    }));
    debugPrint("🗣️ Sent prompt (with image: ${imageBytes != null})");
  }

  void disconnect() {
    _isConnected = false;
    _isSetupComplete = false;
    _isConnecting = false;
    _setupCompleter = null;
    _channel?.sink.close();
    _channel = null;
    debugPrint("🔌 Disconnected");
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  Future<void> _connectInternal() async {
    _isConnecting = true;
    _isConnected = false;
    _isSetupComplete = false;
    _setupCompleter = Completer<void>();

    try {
      debugPrint("🔄 Connecting to WebSocket...");
      _channel = WebSocketChannel.connect(_uri);

      // Wait for the TCP + WebSocket handshake to fully complete.
      // This is the #1 cause of "cannot send" — skipping this means
      // sink.add() fires into a half-open socket.
      await _channel!.ready;
      _isConnected = true;
      debugPrint("🔌 WebSocket handshake complete");

      // Start listening BEFORE sending setup
      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          debugPrint("❌ WebSocket error: $error");
          _onDisconnected();
        },
        onDone: () {
          debugPrint(
              "🔴 WebSocket closed — code: ${_channel?.closeCode}, reason: ${_channel?.closeReason}");
          _onDisconnected();
        },
        cancelOnError: false,
      );

      // Send setup and wait for server to acknowledge it
      _sendSetupMessage();
      await _setupCompleter!.future
          .timeout(const Duration(seconds: 10), onTimeout: () {
        throw TimeoutException("Setup acknowledgement timed out after 10s");
      });

      debugPrint("✅ Ready — setup acknowledged by server");
    } catch (e) {
      debugPrint("❌ Connection failed: $e");
      _isConnected = false;
      _isSetupComplete = false;
      _setupCompleter?.completeError(e);
    } finally {
      _isConnecting = false;
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final String text;
      if (message is List<int>) {
        text = utf8.decode(message);
      } else {
        text = message.toString();
      }

      final data = jsonDecode(text) as Map<String, dynamic>;

      // Server acknowledges our setup message
      if (data.containsKey('setupComplete')) {
        debugPrint("✅ setupComplete received");
        _isSetupComplete = true;
        if (!(_setupCompleter?.isCompleted ?? true)) {
          _setupCompleter!.complete();
        }
        return;
      }

      // Audio transcription response
      if (data['serverContent'] != null) {
        final sc = data['serverContent'] as Map<String, dynamic>;

        if (sc['outputTranscription'] != null) {
          final t = sc['outputTranscription']['text'] as String?;
          if (t != null && t.isNotEmpty) {
            _onMessageReceived?.call(t);
          }
        }

        // Text responses
        if (sc['modelTurn'] != null) {
          final parts = sc['modelTurn']['parts'] as List<dynamic>?;
          for (final part in parts ?? []) {
            final t = part['text'] as String?;
            if (t != null && t.isNotEmpty) {
              _onMessageReceived?.call(t);
            }
          }
        }
      }
    } catch (e) {
      debugPrint("⚠️ Parse error: $e");
    }
  }

  void _sendSetupMessage() {
    _send(jsonEncode({
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
    }));
    debugPrint("📤 Setup message sent");
  }

  /// Raw send — only call after _channel!.ready has resolved.
  void _send(String message) {
    if (_channel == null) {
      debugPrint("⚠️ _send called but channel is null");
      return;
    }
    _channel!.sink.add(message);
  }

  /// Ensures connection is live and setup is acknowledged before any send.
  /// Auto-reconnects if the socket dropped.
  Future<void> _ensureReady() async {
    if (_isConnected && _isSetupComplete) return;

    debugPrint("🔄 Not ready — reconnecting...");
    await _connectInternal();
  }

  void _onDisconnected() {
    _isConnected = false;
    _isSetupComplete = false;
    if (!(_setupCompleter?.isCompleted ?? true)) {
      _setupCompleter!.completeError("WebSocket closed before setup completed");
    }
  }
}