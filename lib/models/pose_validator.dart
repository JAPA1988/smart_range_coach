import 'package:flutter/foundation.dart';

class PoseValidator {
  // Confidence-Schwellwerte
  static const double minKeypointConfidence = 0.6;
  static const double minAverageConfidence = 0.65;
  
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
        if (kDebugMode) debugPrint('⚠️ Low confidence for $key: ${kp['score']}');
        return false;
      }
    }
    
    // Prüfe 2: Mindestens 4 von 6 kritischen Keypoints sichtbar
    int visibleCritical = 0;
    double totalConfidence = 0;
    
    for (final key in criticalKeypoints) {
      if (keypoints.containsKey(key)) {
        final kp = keypoints[key];
        if (kp != null && kp['score'] != null && kp['score'] >= minKeypointConfidence) {
          visibleCritical++;
          totalConfidence += kp['score'] as double;
        }
      }
    }
    
    if (visibleCritical < 4) {
      if (kDebugMode) debugPrint('⚠️ Only $visibleCritical critical keypoints visible');
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
    // Körper muss Schultern UND Hüften haben
    final hasShoulders = 
        isKeypointVisible(keypoints['left_shoulder']) &&
        isKeypointVisible(keypoints['right_shoulder']);
    
    final hasHips = 
        keypoints.containsKey('left_hip') &&
        keypoints.containsKey('right_hip') &&
        (isKeypointVisible(keypoints['left_hip']) ||
         isKeypointVisible(keypoints['right_hip']));
    
    return hasShoulders && hasHips;
  }
}
