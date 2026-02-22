import 'package:flutter/material.dart';
import '../models/pose_frame.dart';

class PoseOverlayPainter extends CustomPainter {
  final PoseFrame? poseFrame;

  PoseOverlayPainter(this.poseFrame);

  static const List<List<String>> connections = [
    // Kopf zu Schultern
    ['nose', 'left_shoulder'],
    ['nose', 'right_shoulder'],

    // Oberkörper
    ['left_shoulder', 'right_shoulder'],
    ['left_shoulder', 'left_elbow'],
    ['left_elbow', 'left_wrist'],
    ['right_shoulder', 'right_elbow'],
    ['right_elbow', 'right_wrist'],

    // Torso
    ['left_shoulder', 'left_hip'],
    ['right_shoulder', 'right_hip'],
    ['left_hip', 'right_hip'],

    // Beine
    ['left_hip', 'left_knee'],
    ['left_knee', 'left_ankle'],
    ['right_hip', 'right_knee'],
    ['right_knee', 'right_ankle'],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Early return wenn kein Frame
    if (poseFrame == null || !poseFrame!.isBodyPresent) {
      return;
    }

    // Farbzuordnung für verschiedene Körperteile
    final keypointColors = {
      // Kopf
      'nose': Colors.cyan,

      // Schultern
      'left_shoulder': Colors.red,
      'right_shoulder': Colors.red,

      // Ellenbogen
      'left_elbow': Colors.orange,
      'right_elbow': Colors.orange,

      // Handgelenke
      'left_wrist': Colors.amber,
      'right_wrist': Colors.amber,

      // Hüften
      'left_hip': Colors.green,
      'right_hip': Colors.green,

      // Knie
      'left_knee': Colors.blue,
      'right_knee': Colors.blue,

      // Knöchel
      'left_ankle': Colors.purple,
      'right_ankle': Colors.purple,
    };

    final linePaint = Paint()
      ..color = Colors.green.withOpacity(0.8)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

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

    // Zeichne Keypoints mit Farben
    for (final kp in poseFrame!.keypoints.values) {
      if (kp.isVisible) {
        final color = keypointColors[kp.label] ?? Colors.white;

        final pointPaint = Paint()
          ..color = color
          ..style = PaintingStyle.fill;

        final center = Offset(kp.x * size.width, kp.y * size.height);

        canvas.drawCircle(
          center,
          6,
          pointPaint,
        );

        // Optional: Confidence-Ring
        final confidencePaint = Paint()
          ..color = Colors.yellow.withOpacity(kp.confidence)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;

        canvas.drawCircle(
          center,
          8,
          confidencePaint,
        );

        final suffix = kp.label.startsWith('left_')
            ? 'l'
            : kp.label.startsWith('right_')
                ? 'r'
                : null;

        if (suffix != null) {
          final textPainter = TextPainter(
            text: TextSpan(
              text: suffix,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          );

          textPainter.layout();
          textPainter.paint(
            canvas,
            center - Offset(textPainter.width / 2, textPainter.height / 2),
          );
        }
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
