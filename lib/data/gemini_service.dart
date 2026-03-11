import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:camera/camera.dart';
import '../domain/agent_intent.dart';

class GeminiService {
  // Replace with your actual API key!
  static const String _apiKey = 'AIzaSyDYvv5O1dqym1XTiUpBN0ftWTNMSmGIlIo';
 
  static final _model = GenerativeModel(
    model: 'gemini-2.5-flash',
    apiKey: _apiKey,
    // Force strict JSON output
    generationConfig: GenerationConfig(responseMimeType: 'application/json'),
  );

  static Future<AgentIntent> analyzeAndRoute(XFile image) async {
    try {
      final bytes = await image.readAsBytes();
     
      // THE AGENTIC PROMPT: Forcing the AI into a deterministic router
      final prompt = TextPart('''
        You are an AI Action Router. Analyze this image and return a JSON object with exactly this structure:
        {
          "intent": "...", // MUST be one of: 'shop_online', 'call_number', 'solve_math', 'general_info'
          "summary": "...", // A conversational summary of what you see or the math solution.
          "actionData": {...} // Data needed for the action.
                              // If 'shop_online', include 'search_query' (e.g., 'Logitech Wireless Mouse').
                              // If 'call_number', include 'phone_number' (e.g., '18005551234').
        }
      ''');
     
      final imagePart = DataPart('image/jpeg', bytes);

      final response = await _model.generateContent([
        Content.multi([prompt, imagePart])
      ]);

      final String jsonString = response.text ?? "{}";
      final Map<String, dynamic> jsonMap = jsonDecode(jsonString);

      return AgentIntent.fromJson(jsonMap);

    } catch (e) {
      debugPrint("AI Error: $e");
      return AgentIntent(
        intent: 'error',
        summary: "Failed to connect to the agent reasoning engine.",
        actionData: {}
      );
    }
  }
}