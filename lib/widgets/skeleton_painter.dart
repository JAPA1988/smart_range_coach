import 'package:flutter/material.dart';

class SkeletonPainter extends CustomPainter {
  final Map<String, dynamic> keypoints;
  final bool showLabels;
  final double minConfidence;

  SkeletonPainter({
    required this.keypoints,
    this.showLabels = false,
    this.minConfidence = 0.3,
  });

  static const List<List<String>> _connections = [
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
    const leftSideColor = Color(0xFF2DD4BF);
    const rightSideColor = Color(0xFFFB923C);
    const centerColor = Color(0xFFFCD34D);

    final linePaint = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final jointPaint = Paint()..style = PaintingStyle.fill;

    for (final pair in _connections) {
      final p1 = _getPoint(pair[0], size);
      final p2 = _getPoint(pair[1], size);
      if (p1 == null || p2 == null) continue;
      linePaint.color = _edgeColor(
        pair[0],
        pair[1],
        leftSideColor,
        rightSideColor,
        centerColor,
      );
      canvas.drawLine(p1, p2, linePaint);
    }

    keypoints.forEach((name, point) {
      final p = _getPoint(name, size);
      if (p == null) return;
      jointPaint.color = _pointColor(
        name,
        leftSideColor,
        rightSideColor,
        centerColor,
      );
      canvas.drawCircle(p, 4, jointPaint);

      if (showLabels) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: name,
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, p + const Offset(6, -6));
      }
    });
  }

  Offset? _getPoint(String name, Size size) {
    final point = keypoints[name];
    if (point == null) return null;

    final x = _readValue(point, 'x');
    final y = _readValue(point, 'y');
    final confidence = _readConfidence(point);

    if (x == null || y == null) return null;
    if (confidence != null && confidence < minConfidence) return null;

    return Offset(x * size.width, y * size.height);
  }

  double? _readValue(dynamic point, String field) {
    if (point is Map) {
      final value = point[field];
      if (value is num) return value.toDouble();
      return null;
    }

    try {
      final dynamic value = field == 'x' ? point.x : point.y;
      if (value is num) return value.toDouble();
    } catch (_) {}

    return null;
  }

  double? _readConfidence(dynamic point) {
    if (point is Map) {
      final value = point['score'] ?? point['confidence'] ?? point['visibility'];
      if (value is num) return value.toDouble();
      return null;
    }

    try {
      final dynamic value = point.confidence;
      if (value is num) return value.toDouble();
    } catch (_) {}

    return null;
  }

  Color _edgeColor(
    String start,
    String end,
    Color left,
    Color right,
    Color center,
  ) {
    final isLeft = start.startsWith('left_') && end.startsWith('left_');
    final isRight = start.startsWith('right_') && end.startsWith('right_');

    if (isLeft) return left;
    if (isRight) return right;
    return center;
  }

  Color _pointColor(
    String name,
    Color left,
    Color right,
    Color center,
  ) {
    if (name.startsWith('left_')) return left;
    if (name.startsWith('right_')) return right;
    return center;
  }

  @override
  bool shouldRepaint(covariant SkeletonPainter oldDelegate) {
    return oldDelegate.keypoints != keypoints ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.minConfidence != minConfidence;
  }
}
