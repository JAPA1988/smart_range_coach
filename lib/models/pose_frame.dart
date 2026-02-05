import 'pose_validator.dart';

class PoseFrame {
  final Duration timestamp;
  final int frameIndex;
  final Map<String, Keypoint> keypoints;
  final double qualityScore;
  
  PoseFrame({
    required this.timestamp,
    required this.frameIndex,
    required this.keypoints,
    required this.qualityScore,
  });
  
  factory PoseFrame.fromJson(Map<String, dynamic> json) {
    final keypointsJson = json['keypoints'] as Map<String, dynamic>;
    final keypoints = <String, Keypoint>{};
    
    keypointsJson.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        keypoints[key] = Keypoint.fromJson(key, value);
      }
    });
    
    return PoseFrame(
      timestamp: Duration(milliseconds: json['timestamp_ms'] as int),
      frameIndex: json['frame_index'] as int,
      keypoints: keypoints,
      qualityScore: json['quality_score'] as double? ?? 0.0,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'timestamp_ms': timestamp.inMilliseconds,
    'frame_index': frameIndex,
    'quality_score': qualityScore,
    'keypoints': keypoints.map((key, kp) => MapEntry(key, kp.toJson())),
  };
  
  bool get isValid => PoseValidator.isKeypointsValid(
    keypoints.map((key, kp) => MapEntry(key, kp.toJson()))
  );
  
  Keypoint? getKeypoint(String name) => keypoints[name];
}

class Keypoint {
  final String label;
  final double x;
  final double y;
  final double confidence;
  
  Keypoint({
    required this.label,
    required this.x,
    required this.y,
    required this.confidence,
  });
  
  factory Keypoint.fromJson(String label, Map<String, dynamic> json) {
    return Keypoint(
      label: label,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      confidence: (json['score'] as num).toDouble(),
    );
  }
  
  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'score': confidence,
  };
  
  bool get isVisible => confidence >= PoseValidator.minKeypointConfidence;
  
  Keypoint lerp(Keypoint other, double t) {
    return Keypoint(
      label: label,
      x: x + (other.x - x) * t,
      y: y + (other.y - y) * t,
      confidence: confidence + (other.confidence - confidence) * t,
    );
  }
}
