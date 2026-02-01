import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;

class MediaPipeManager {
  static PoseDetector? _detector;
  
  static Future<void> init() async {
    if (_detector != null) return;
    
    try {
      final options = PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.accurate,
      );
      _detector = PoseDetector(options: options);
      if (kDebugMode) debugPrint('MediaPipe Pose initialized');
    } catch (e) {
      if (kDebugMode) debugPrint('MediaPipe init failed: $e');
    }
  }
  
  static Future<Map<String, dynamic>?> analyzePoseFromRGBA(
    Uint8List rgba, 
    int width, 
    int height,
  ) async {
    if (_detector == null) await init();
    if (_detector == null) return null;
    
    try {
      // Konvertiere RGBA zu InputImage
      final inputImage = InputImage.fromBytes(
        bytes: rgba,
        metadata: InputImageMetadata(
          size: ui.Size(width.toDouble(), height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.bgra8888,
          bytesPerRow: width * 4,
        ),
      );
      
      final poses = await _detector!.processImage(inputImage);
      
      if (poses.isEmpty) return null;
      
      final pose = poses.first;
      final landmarks = pose.landmarks;
      
      // Extrahiere alle 33 Keypoints (MediaPipe landmarks ist ein Map)
      return {
        'keypoints': {
          for (var entry in landmarks.entries)
            _getLandmarkName(entry.key.index): {
              'x': entry.value.x / width,  // Normalisiert 0..1
              'y': entry.value.y / height,
              'z': entry.value.z,
              'visibility': entry.value.likelihood,
            }
        },
        'raw_landmarks': [
          for (var landmark in landmarks.values)
            {
              'x': landmark.x,
              'y': landmark.y,
              'z': landmark.z,
              'visibility': landmark.likelihood,
            }
        ],
      };
    } catch (e) {
      if (kDebugMode) debugPrint('MediaPipe analysis error: $e');
      return null;
    }
  }
  
  static String _getLandmarkName(int index) {
    const names = [
      'nose', 'left_eye_inner', 'left_eye', 'left_eye_outer',
      'right_eye_inner', 'right_eye', 'right_eye_outer',
      'left_ear', 'right_ear', 'mouth_left', 'mouth_right',
      'left_shoulder', 'right_shoulder',
      'left_elbow', 'right_elbow',
      'left_wrist', 'right_wrist',
      'left_pinky', 'right_pinky',
      'left_index', 'right_index',
      'left_thumb', 'right_thumb',
      'left_hip', 'right_hip',
      'left_knee', 'right_knee',
      'left_ankle', 'right_ankle',
      'left_heel', 'right_heel',
      'left_foot_index', 'right_foot_index',
    ];
    return index < names.length ? names[index] : 'unknown_$index';
  }
  
  static void dispose() {
    _detector?.close();
    _detector = null;
  }
}
