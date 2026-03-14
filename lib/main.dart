import 'package:flutter/material.dart';
import 'package:camera/camera.dart'; // Import camera
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'prsentation/camera_screen.dart'; 

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  
  // Bring this back!
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Camera error: $e');
  }
  
  runApp(const GeminiLensApp());
}

class GeminiLensApp extends StatelessWidget {
  const GeminiLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Multimodal Agent',
      theme: ThemeData.dark(),
      debugShowCheckedModeBanner: false,
      home: VoiceAgentScreen(cameras: cameras), // Pass cameras to the UI
    );
  }
}
