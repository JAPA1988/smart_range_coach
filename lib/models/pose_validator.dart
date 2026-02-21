import 'package:flutter/foundation.dart';

class PoseValidator {
  // Confidence-Schwellwerte
  static const double minKeypointConfidence = 0.35;
  static const double minAverageConfidence = 0.45;
  static const double minBodyPresenceConfidence = 0.25;

  // Wichtige Keypoints für Golf-Analyse
  static const List<String> criticalKeypoints = [
    'left_shoulder',
    'right_shoulder',
    'left_hip',
    'right_hip',
    'left_elbow',
    'right_elbow',
  ];

  static const List<String> essentialKeypoints = [
    'left_shoulder',
    'right_shoulder',
  ];

  /// Validiert einen kompletten Frame
  static bool isFrameValid(Map<String, dynamic> frame) {
    if (!frame.containsKey('keypoints')) return false;

    final keypoints = frame['keypoints'] as Map<String, dynamic>;
    return isKeypointsValid(keypoints);
  }

  /// Validiert Keypoints-Map
  static bool isKeypointsValid(Map<String, dynamic> keypoints) {
    // Prüfe 1: Alle essentiellen Keypoints müssen existieren
    for (final key in essentialKeypoints) {
      if (!keypoints.containsKey(key)) {
        if (kDebugMode) debugPrint('⚠️ Missing essential keypoint: $key');
        return false;
      }

      final kp = keypoints[key];
      if (kp == null || kp['score'] == null) return false;

      if (kp['score'] < minKeypointConfidence) {
        if (kDebugMode)
          debugPrint('⚠️ Low confidence for $key: ${kp['score']}');
        return false;
      }
    }

    // Prüfe 2: Mindestens 3 von 6 kritischen Keypoints sichtbar
    int visibleCritical = 0;
    double totalConfidence = 0;

    for (final key in criticalKeypoints) {
      if (keypoints.containsKey(key)) {
        final kp = keypoints[key];
        if (kp != null &&
            kp['score'] != null &&
            kp['score'] >= minKeypointConfidence) {
          visibleCritical++;
          totalConfidence += kp['score'] as double;
        }
      }
    }

    if (visibleCritical < 3) {
      if (kDebugMode)
        debugPrint('⚠️ Only $visibleCritical critical keypoints visible');
      return false;
    }

    // Prüfe 3: Durchschnittliche Confidence
    final avgConfidence = totalConfidence / visibleCritical;
    if (avgConfidence < minAverageConfidence) {
      if (kDebugMode) debugPrint('⚠️ Low average confidence: $avgConfidence');
      return false;
    }

    return true;
  }

  /// Prüft ob ein Keypoint einzeln valide ist
  static bool isKeypointVisible(Map<String, dynamic>? keypoint) {
    if (keypoint == null) return false;
    if (!keypoint.containsKey('score')) return false;
    return (keypoint['score'] as double) >= minKeypointConfidence;
  }

  /// Berechnet Pose-Qualitäts-Score (0.0 - 1.0)
  static double calculatePoseQuality(Map<String, dynamic> keypoints) {
    double totalScore = 0;
    int count = 0;

    for (final key in criticalKeypoints) {
      if (keypoints.containsKey(key)) {
        final kp = keypoints[key];
        if (kp != null && kp['score'] != null) {
          totalScore += kp['score'] as double;
          count++;
        }
      }
    }

    return count > 0 ? totalScore / count : 0.0;
  }

  /// Prüft ob Körper im Bild ist (nicht nur Artefakte)
  static bool isBodyPresent(Map<String, dynamic> keypoints) {
    final leftShoulder = keypoints['left_shoulder'] as Map<String, dynamic>?;
    final rightShoulder = keypoints['right_shoulder'] as Map<String, dynamic>?;
    final leftHip = keypoints['left_hip'] as Map<String, dynamic>?;
    final rightHip = keypoints['right_hip'] as Map<String, dynamic>?;

    final leftShoulderScore =
        (leftShoulder?['score'] as num?)?.toDouble() ?? 0.0;
    final rightShoulderScore =
        (rightShoulder?['score'] as num?)?.toDouble() ?? 0.0;
    final leftHipScore = (leftHip?['score'] as num?)?.toDouble() ?? 0.0;
    final rightHipScore = (rightHip?['score'] as num?)?.toDouble() ?? 0.0;

    final hasShoulders = leftShoulderScore >= minBodyPresenceConfidence &&
        rightShoulderScore >= minBodyPresenceConfidence;
    final hasHip = leftHipScore >= minBodyPresenceConfidence ||
        rightHipScore >= minBodyPresenceConfidence;
    if (!hasShoulders || !hasHip) return false;

    final leftShoulderX = (leftShoulder?['x'] as num?)?.toDouble();
    final rightShoulderX = (rightShoulder?['x'] as num?)?.toDouble();
    final leftShoulderY = (leftShoulder?['y'] as num?)?.toDouble();
    final rightShoulderY = (rightShoulder?['y'] as num?)?.toDouble();
    final leftHipY = (leftHip?['y'] as num?)?.toDouble();
    final rightHipY = (rightHip?['y'] as num?)?.toDouble();

    if (leftShoulderX == null ||
        rightShoulderX == null ||
        leftShoulderY == null ||
        rightShoulderY == null ||
        leftHipY == null ||
        rightHipY == null) {
      return true;
    }

    final shoulderSpan = (leftShoulderX - rightShoulderX).abs();
    if (shoulderSpan < 0.015 || shoulderSpan > 0.95) return false;

    final shoulderCenterY = (leftShoulderY + rightShoulderY) / 2.0;
    final hipCenterY = (leftHipY + rightHipY) / 2.0;
    final torsoHeight = hipCenterY - shoulderCenterY;
    if (torsoHeight < 0.005 || torsoHeight > 0.9) return false;

    return true;
  }
}
