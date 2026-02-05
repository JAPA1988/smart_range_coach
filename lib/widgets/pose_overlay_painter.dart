import 'package:flutter/material.dart';
import '../models/pose_frame.dart';
import '../models/pose_validator.dart';

class PoseOverlayPainter extends CustomPainter {
  final PoseFrame? poseFrame;
  
  PoseOverlayPainter(this.poseFrame);
  
  static const List<List<String>> connections = [
    ['left_shoulder', 'right_shoulder'],
    ['left_shoulder', 'left_elbow'],
    ['left_elbow', 'left_wrist'],
    ['right_shoulder', 'right_elbow'],
    ['right_elbow', 'right_wrist'],
    ['left_shoulder', 'left_hip'],
    ['right_shoulder', 'right_hip'],
    ['left_hip', 'right_hip'],
    ['left_hip', 'left_knee'],
    ['left_knee', 'left_ankle'],
    ['right_hip', 'right_knee'],
    ['right_knee', 'right_ankle'],
  ];
  
  @override
  void paint(Canvas canvas, Size size) {
    // Early return wenn kein Frame
    if (poseFrame == null) return;
    
    // Early return wenn Frame nicht valide
    if (!poseFrame!.isValid) return;
    
    // Early return wenn kein Körper erkannt
    if (!PoseValidator.isBodyPresent(
      poseFrame!.keypoints.map((k, v) => MapEntry(k, v.toJson()))
    )) {
      return;
    }
    
    final linePaint = Paint()
      ..color = Colors.green.withOpacity(0.8)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    
    final pointPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    
    // Zeichne Verbindungen
    for (final conn in connections) {
      final kp1 = poseFrame!.getKeypoint(conn[0]);
      final kp2 = poseFrame!.getKeypoint(conn[1]);
      
      if (kp1 != null && kp2 != null && kp1.isVisible && kp2.isVisible) {
        canvas.drawLine(
          Offset(kp1.x * size.width, kp1.y * size.height),
          Offset(kp2.x * size.width, kp2.y * size.height),
          linePaint,
        );
      }
    }
    
    // Zeichne Keypoints
    for (final kp in poseFrame!.keypoints.values) {
      if (kp.isVisible) {
        canvas.drawCircle(
          Offset(kp.x * size.width, kp.y * size.height),
          6,
          pointPaint,
        );
        
        // Optional: Confidence-Ring
        final confidencePaint = Paint()
          ..color = Colors.yellow.withOpacity(kp.confidence)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        
        canvas.drawCircle(
          Offset(kp.x * size.width, kp.y * size.height),
          8,
          confidencePaint,
        );
      }
    }
    
    // Optional: Qualitäts-Indikator
    _drawQualityIndicator(canvas, size);
  }
  
  void _drawQualityIndicator(Canvas canvas, Size size) {
    if (poseFrame == null) return;
    
    final quality = poseFrame!.qualityScore;
    final color = quality > 0.8 
        ? Colors.green 
        : quality > 0.6 
            ? Colors.yellow 
            : Colors.orange;
    
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Quality: ${(quality * 100).toStringAsFixed(0)}%',
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              offset: Offset(1, 1),
              blurRadius: 3,
              color: Colors.black,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    textPainter.paint(canvas, Offset(10, 10));
  }
  
  @override
  bool shouldRepaint(covariant PoseOverlayPainter oldDelegate) {
    return oldDelegate.poseFrame != poseFrame;
  }
}
