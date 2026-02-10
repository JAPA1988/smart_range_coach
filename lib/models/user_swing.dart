class UserSwing {
  final String id;
  final String videoPath;
  final DateTime recordedAt;
  final List<FrameData> frames;
  final Map<String, UserKeyPosition>? markedPositions;
  final AnalysisStatus status;

  UserSwing({
    required this.id,
    required this.videoPath,
    required this.recordedAt,
    required this.frames,
    this.markedPositions,
    required this.status,
  });

  bool isPositionMarked(String positionName) {
    return markedPositions?.containsKey(positionName) ?? false;
  }

  int get markedPositionsCount => markedPositions?.length ?? 0;
  bool get allPositionsMarked => markedPositionsCount == 7;

  UserSwing copyWith({
    String? id,
    String? videoPath,
    DateTime? recordedAt,
    List<FrameData>? frames,
    Map<String, UserKeyPosition>? markedPositions,
    AnalysisStatus? status,
  }) {
    return UserSwing(
      id: id ?? this.id,
      videoPath: videoPath ?? this.videoPath,
      recordedAt: recordedAt ?? this.recordedAt,
      frames: frames ?? this.frames,
      markedPositions: markedPositions ?? this.markedPositions,
      status: status ?? this.status,
    );
  }
}

class UserKeyPosition {
  final int frameIndex;
  final int timestampMs;
  final Map<String, Keypoint> keypoints;
  final DateTime markedAt;
  final String? skeletonImagePath;

  UserKeyPosition({
    required this.frameIndex,
    required this.timestampMs,
    required this.keypoints,
    required this.markedAt,
    this.skeletonImagePath,
  });

  UserKeyPosition copyWith({
    int? frameIndex,
    int? timestampMs,
    Map<String, Keypoint>? keypoints,
    DateTime? markedAt,
    String? skeletonImagePath,
  }) {
    return UserKeyPosition(
      frameIndex: frameIndex ?? this.frameIndex,
      timestampMs: timestampMs ?? this.timestampMs,
      keypoints: keypoints ?? this.keypoints,
      markedAt: markedAt ?? this.markedAt,
      skeletonImagePath: skeletonImagePath ?? this.skeletonImagePath,
    );
  }
}

class FrameData {
  final int frameIndex;
  final int timestampMs;
  final Map<String, Keypoint> keypoints;

  FrameData({
    required this.frameIndex,
    required this.timestampMs,
    required this.keypoints,
  });

  factory FrameData.fromJson(Map<String, dynamic> json) {
    final keypointsJson = json['keypoints'] as Map<String, dynamic>? ?? {};
    final keypoints = <String, Keypoint>{};

    keypointsJson.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        keypoints[key] = Keypoint.fromJson(value);
      }
    });

    return FrameData(
      frameIndex: json['frame_index'] ?? 0,
      timestampMs: json['timestamp_ms'] ?? 0,
      keypoints: keypoints,
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
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      confidence: (json['score'] as num?)?.toDouble() ??
          (json['confidence'] as num?)?.toDouble() ??
          0.0,
    );
  }
}

enum AnalysisStatus {
  recording,
  uploading,
  analyzing,
  completed,
  failed,
}
