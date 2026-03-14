# 👁️ Gemini Lens: Hybrid Edge-to-Cloud Multimodal Agent

Gemini Lens is a real-time, voice-activated multimodal AI assistant built in Flutter. It replicates the complex stateful interactions of enterprise AI agents (like Gemini Live) by combining continuous on-device environmental scanning with low-latency conversational cloud responses.

This project was built to demonstrate advanced mobile architecture, specifically focusing on **Hybrid Edge-to-Cloud ML pipelines**, **WebSocket streaming**, and **asynchronous hardware thread management**.

---

## 🧠 System Architecture

To minimize cloud compute costs, reduce network payloads, and preserve battery life, this project implements a **Hybrid Edge-to-Cloud Pipeline**.

```mermaid
graph TD
    classDef edge fill:#34A853,stroke:#188038,stroke-width:2px,color:white,font-weight:bold;
    classDef cloud fill:#4285F4,stroke:#1A73E8,stroke-width:2px,color:white,font-weight:bold;
    classDef ui fill:#FBBC05,stroke:#F29900,stroke-width:2px,color:black,font-weight:bold;

    Camera["📷 Raw Camera Feed (60 FPS)"]:::ui
    TFLite["⚙️ Edge AI: TensorFlow Lite\n(MobileNet Object Detection)"]:::edge
    Trigger{"Confidence > 95%?"}:::edge
    WebSocket["🔌 Bidirectional WebSocket\n(Gemini Live API)"]:::cloud
    TTS["🔊 Native Text-to-Speech\n(Sentence Buffered)"]:::ui
    UserVoice["🎙️ User Voice (Speech-to-Text)"]:::ui

    Camera -->|2 FPS Polling| TFLite
    TFLite --> Trigger
    Trigger -->|Yes: Trigger Cloud Handoff| WebSocket
    Trigger -->|No: Ignore Frame| TFLite
    
    UserVoice -->|Manual Override| WebSocket
    
    WebSocket -->|Fragmented JSON Stream| TTS
