import 'dart:math';

class SwingComparison {
  // MoveNet Keypoints für Golf (17 total)
  static const List<String> golfKeypoints = [
    'left_shoulder', 'right_shoulder',
    'left_elbow', 'right_elbow',
    'left_wrist', 'right_wrist',
    'left_hip', 'right_hip',
    'left_knee', 'right_knee',
  ];
  
  /// Vergleicht User-Schwung mit Profi-Schwung (MoveNet 17 Keypoints)
  static Map<String, dynamic> compareSwings(
    List<Map<String, dynamic>> userFrames,
    List<Map<String, dynamic>> proFrames,
  ) {
    if (userFrames.isEmpty || proFrames.isEmpty) {
      return {'error': 'Keine Daten zum Vergleichen'};
    }
    
    // 1. Normalisiere beide Schwünge
    final normalizedUser = _normalizeSwing(userFrames);
    final normalizedPro = _normalizeSwing(proFrames);
    
    // 2. Berechne Keypoint-Differenzen
    final differences = <String, List<double>>{};
    
    for (final keypoint in golfKeypoints) {
      differences[keypoint] = [];
      
      for (int i = 0; i < normalizedUser.length; i++) {
        // Finde zeitlich passenden Profi-Frame
        final proIndex = _mapUserFrameToProFrame(i, normalizedUser.length, normalizedPro.length);
        
        final userKp = normalizedUser[i]['keypoints'][keypoint];
        final proKp = normalizedPro[proIndex]['keypoints'][keypoint];
        
        if (userKp != null && proKp != null && 
            userKp['score'] > 0.5 && proKp['score'] > 0.5) {
          
          // 2D Euklidische Distanz (MoveNet hat kein Z)
          final distance = _calculate2DDistance(userKp, proKp);
          differences[keypoint]!.add(distance);
        }
      }
    }
    
    // 3. Berechne Gesamtscore
    double totalScore = 0;
    int validKeypoints = 0;
    
    final keypointScores = <String, double>{};
    
    differences.forEach((keypoint, diffs) {
      if (diffs.isNotEmpty) {
        final avgDiff = diffs.reduce((a, b) => a + b) / diffs.length;
        final score = (1.0 - avgDiff.clamp(0.0, 1.0)) * 100;
        keypointScores[keypoint] = score;
        totalScore += score;
        validKeypoints++;
      }
    });
    
    final overallScore = validKeypoints > 0 ? totalScore / validKeypoints : 0.0;
    
    // 4. Generiere Empfehlungen
    final recommendations = _generateRecommendations(keypointScores);
    
    // 5. Finde beste und schlechteste Keypoints
    final sortedScores = keypointScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return {
      'overall_score': overallScore,
      'keypoint_scores': keypointScores,
      'best_keypoints': sortedScores.take(3).map((e) => e.key).toList(),
      'worst_keypoints': sortedScores.reversed.take(3).map((e) => e.key).toList(),
      'recommendations': recommendations,
      'differences': differences,
      'user_frame_count': userFrames.length,
      'pro_frame_count': proFrames.length,
    };
  }
  
  /// Normalisiert Schwung (unabhängig von Körpergröße/Position)
  static List<Map<String, dynamic>> _normalizeSwing(List<Map<String, dynamic>> frames) {
    if (frames.isEmpty) return frames;
    
    // Berechne Hüft-Center als Referenzpunkt (erster Frame)
    final firstFrame = frames.first['keypoints'];
    final leftHip = firstFrame['left_hip'];
    final rightHip = firstFrame['right_hip'];
    
    if (leftHip == null || rightHip == null) return frames;
    
    final hipCenterX = (leftHip['x'] + rightHip['x']) / 2;
    final hipCenterY = (leftHip['y'] + rightHip['y']) / 2;
    
    // Berechne Körpergröße für Skalierung
    final leftShoulder = firstFrame['left_shoulder'];
    final rightShoulder = firstFrame['right_shoulder'];
    
    if (leftShoulder == null || rightShoulder == null) return frames;
    
    final shoulderY = (leftShoulder['y'] + rightShoulder['y']) / 2;
    final bodyHeight = (shoulderY - hipCenterY).abs();
    
    if (bodyHeight == 0) return frames;
    
    // Normalisiere alle Frames
    return frames.map((frame) {
      final keypoints = Map<String, dynamic>.from(frame['keypoints'] ?? {});
      
      keypoints.forEach((key, point) {
        if (point != null && point is Map) {
          keypoints[key] = {
            'x': (point['x'] - hipCenterX) / bodyHeight,
            'y': (point['y'] - hipCenterY) / bodyHeight,
            'score': point['score'] ?? 0.0,
          };
        }
      });
      
      return {
        'timestamp_ms': frame['timestamp_ms'],
        'keypoints': keypoints,
      };
    }).toList();
  }
  
  /// Mapped User-Frame-Index zu entsprechendem Profi-Frame-Index
  static int _mapUserFrameToProFrame(int userIndex, int userTotal, int proTotal) {
    if (userTotal <= 1 || proTotal <= 1) return 0;
    final ratio = userIndex / (userTotal - 1);
    return (ratio * (proTotal - 1)).round().clamp(0, proTotal - 1);
  }
  
  /// Berechnet 2D-Distanz zwischen zwei Keypoints
  static double _calculate2DDistance(Map<String, dynamic> p1, Map<String, dynamic> p2) {
    return sqrt(
      pow(p1['x'] - p2['x'], 2) +
      pow(p1['y'] - p2['y'], 2)
    );
  }
  
  /// Generiert spezifische Empfehlungen basierend auf Scores
  static List<String> _generateRecommendations(Map<String, double> scores) {
    final recommendations = <String>[];
    
    scores.forEach((keypoint, score) {
      if (score < 70) {
        if (keypoint.contains('shoulder')) {
          if (keypoint.contains('left')) {
            recommendations.add('Linke Schulter: Mehr Rotation im Backswing (aktuell ${score.toStringAsFixed(0)}%)');
          } else {
            recommendations.add('Rechte Schulter: Bessere Position bei Impact (aktuell ${score.toStringAsFixed(0)}%)');
          }
        } else if (keypoint.contains('hip')) {
          recommendations.add('Huefte: Staerkere Rotation fuer mehr Power (aktuell ${score.toStringAsFixed(0)}%)');
        } else if (keypoint.contains('elbow')) {
          if (keypoint.contains('left')) {
            recommendations.add('Linker Ellenbogen: Naeher am Koerper fuehren');
          } else {
            recommendations.add('Rechter Ellenbogen: Position im Downswing verbessern');
          }
        } else if (keypoint.contains('wrist')) {
          recommendations.add('Handgelenk: Timing des Release verbessern (aktuell ${score.toStringAsFixed(0)}%)');
        } else if (keypoint.contains('knee')) {
          recommendations.add('Knie: Stabilere Beugung waehrend des Schwungs (aktuell ${score.toStringAsFixed(0)}%)');
        }
      }
    });
    
    if (recommendations.isEmpty) {
      recommendations.add('Hervorragender Schwung! Sehr nah am Profi-Level!');
    } else if (recommendations.length > 5) {
      recommendations.add('Fokussiere dich zuerst auf die wichtigsten 3 Punkte!');
    }
    
    return recommendations.take(6).toList();
  }
}
