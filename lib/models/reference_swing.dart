class ReferenceSwing {
  static const Map<String, String> _imageNameMap = {
    'address': 'adress',
  };

  final String swingId;
  final String golferName;
  final String clubType;
  final String skillLevel;
  final VideoInfo videoInfo;
  final List<String> keyPositions;
  final Map<String, KeyPosition> positions;
  final Map<String, PositionAnalysis> analysis;

  ReferenceSwing({
    required this.swingId,
    required this.golferName,
    required this.clubType,
    required this.skillLevel,
    required this.videoInfo,
    required this.keyPositions,
    required this.positions,
    required this.analysis,
  });

  factory ReferenceSwing.fromJson(
    Map<String, dynamic> metadata,
    Map<String, dynamic> keyPositionsJson,
    Map<String, dynamic> analysisJson,
  ) {
    return ReferenceSwing(
      swingId: metadata['swing_id'],
      golferName: metadata['golfer_name'],
      clubType: metadata['club_type'],
      skillLevel: metadata['skill_level'],
      videoInfo: VideoInfo.fromJson(metadata['video_info']),
      keyPositions: List<String>.from(metadata['key_positions']),
      positions: (keyPositionsJson as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, KeyPosition.fromJson(value)),
      ),
      analysis: (analysisJson as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, PositionAnalysis.fromJson(value)),
      ),
    );
  }

  String get assetBasePath => 'assets/reference_swings/$swingId';
  String get videoPath => '$assetBasePath/video.mp4';
  String imagePathForPosition(String position) {
    final mapped = _imageNameMap[position] ?? position;
    return '$assetBasePath/images/$mapped.jpg';
  }
}

class VideoInfo {
  final double fps;
  final int width;
  final int height;
  final int totalFrames;
  final double durationSeconds;

  VideoInfo({
    required this.fps,
    required this.width,
    required this.height,
    required this.totalFrames,
    required this.durationSeconds,
  });

  factory VideoInfo.fromJson(Map<String, dynamic> json) {
    return VideoInfo(
      fps: json['fps'].toDouble(),
      width: json['width'],
      height: json['height'],
      totalFrames: json['total_frames'],
      durationSeconds: json['duration_seconds'].toDouble(),
    );
  }
}

class KeyPosition {
  final int frame;
  final int timestampMs;
  final Map<String, Keypoint> keypoints;

  KeyPosition({
    required this.frame,
    required this.timestampMs,
    required this.keypoints,
  });

  factory KeyPosition.fromJson(Map<String, dynamic> json) {
    return KeyPosition(
      frame: json['frame'],
      timestampMs: json['timestamp_ms'],
      keypoints: (json['keypoints'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, Keypoint.fromJson(value)),
      ),
    );
  }
}

class Keypoint {
  final double x;
  final double y;
  final double confidence;

  Keypoint({
    required this.x,
    required this.y,
    required this.confidence,
  });

  factory Keypoint.fromJson(Map<String, dynamic> json) {
    return Keypoint(
      x: json['x'].toDouble(),
      y: json['y'].toDouble(),
      confidence: json['confidence'].toDouble(),
    );
  }
}

class PositionAnalysis {
  final double spineAngle;
  final double xFactor;
  final double shoulderRotation;
  final double hipRotation;
  final double leftArmAngle;
  final double rightArmAngle;
  final double leftKneeAngle;
  final double rightKneeAngle;

  PositionAnalysis({
    required this.spineAngle,
    required this.xFactor,
    required this.shoulderRotation,
    required this.hipRotation,
    required this.leftArmAngle,
    required this.rightArmAngle,
    required this.leftKneeAngle,
    required this.rightKneeAngle,
  });

  factory PositionAnalysis.fromJson(Map<String, dynamic> json) {
    return PositionAnalysis(
      spineAngle: json['spine_angle']?.toDouble() ?? 0.0,
      xFactor: json['x_factor']?.toDouble() ?? 0.0,
      shoulderRotation: json['shoulder_rotation']?.toDouble() ?? 0.0,
      hipRotation: json['hip_rotation']?.toDouble() ?? 0.0,
      leftArmAngle: json['left_arm_angle']?.toDouble() ?? 0.0,
      rightArmAngle: json['right_arm_angle']?.toDouble() ?? 0.0,
      leftKneeAngle: json['left_knee_angle']?.toDouble() ?? 0.0,
      rightKneeAngle: json['right_knee_angle']?.toDouble() ?? 0.0,
    );
  }
}
