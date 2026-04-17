package com.yourcompany.gemini_lens

import android.graphics.BitmapFactory
import androidx.annotation.NonNull
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "mediapipe_channel"
    private var handLandmarker: HandLandmarker? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initializeHandLandmarker" -> {
                    setupHandLandmarker()
                    result.success(null)
                }
                "detectHands" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val width = call.argument<Int>("width")!!
                    val height = call.argument<Int>("height")!!
                    detectHands(bytes!!, width, height, result)
                }
                "close" -> {
                    handLandmarker?.close()
                    handLandmarker = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setupHandLandmarker() {
        val baseOptions = BaseOptions.builder()
            .setModelAssetPath("flutter_assets/assets/models/hand_landmarker.task")
            .setDelegate(Delegate.GPU)
            .build()
        val options = HandLandmarker.HandLandmarkerOptions.builder()
            .setBaseOptions(baseOptions)
            .setRunningMode(RunningMode.IMAGE)
            .setNumHands(2)
            .build()
        handLandmarker = HandLandmarker.createFromOptions(options)
    }

    private fun detectHands(bytes: ByteArray, width: Int, height: Int, result: MethodChannel.Result) {
        if (handLandmarker == null) {
            result.error("NOT_INITIALIZED", "HandLandmarker not initialized", null)
            return
        }
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        val mpImage = BitmapImageBuilder(bitmap).build()
        val detectionResult = handLandmarker?.detect(mpImage)

        val landmarksList = mutableListOf<Map<String, Any>>()
        detectionResult?.landmarks()?.forEachIndexed { handIndex, landmarks ->
            val points = landmarks.map { landmark ->
                mapOf(
                    "x" to landmark.x(),
                    "y" to landmark.y(),
                    "z" to landmark.z()
                )
            }
            landmarksList.add(mapOf(
                "handIndex" to handIndex,
                "landmarks" to points
            ))
        }
        result.success(landmarksList)
    }
}