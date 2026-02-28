import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/pose_frame.dart' as pose;
import 'pose_overlay_painter.dart';

class ProProjectionRasterView extends StatelessWidget {
  final pose.PoseFrame poseFrame;
  final double sideCropCm;
  final bool rightHalfOnly;
  final double projectionShiftX;
  final double projectionShiftCm;
  final bool showGrid;
  final bool showSpineAngleMarker;
  final double minConfidence;
  final Color backgroundColor;

  const ProProjectionRasterView({
    super.key,
    required this.poseFrame,
    this.sideCropCm = 1.0,
    this.rightHalfOnly = true,
    this.projectionShiftX = 0.25,
    this.projectionShiftCm = 0.3,
    this.showGrid = true,
    this.showSpineAngleMarker = false,
    this.minConfidence = 0.35,
    this.backgroundColor = Colors.black,
  });

  double _cmToLogicalPx(double cm) {
    const logicalPixelsPerInch = 160.0;
    return (cm / 2.54) * logicalPixelsPerInch;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideCropPx = _cmToLogicalPx(sideCropCm);

        Widget content = Container(
          color: backgroundColor,
          child: Stack(
            children: [
              if (showGrid)
                Positioned.fill(
                  child: CustomPaint(painter: _ComparisonGridPainter()),
                ),
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, innerConstraints) {
                    return Transform.translate(
                      offset: Offset(
                        innerConstraints.maxWidth * projectionShiftX +
                            _cmToLogicalPx(projectionShiftCm),
                        0,
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: PoseOverlayPainter(
                                poseFrame,
                                requireBodyPresence: false,
                                minConfidence: minConfidence,
                              ),
                            ),
                          ),
                          if (showSpineAngleMarker)
                            Positioned.fill(
                              child: CustomPaint(
                                painter:
                                    _ProSpineAnglePainter(poseFrame: poseFrame),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );

        if (rightHalfOnly) {
          content = LayoutBuilder(
            builder: (context, halfConstraints) {
              return ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.5,
                  child: Transform.translate(
                    offset: Offset(-halfConstraints.maxWidth / 2, 0),
                    child: content,
                  ),
                ),
              );
            },
          );
        }

        if (sideCropPx > 0) {
          content = ClipRect(
            clipper: _CenteredHorizontalCropClipper(sideCropPx: sideCropPx),
            child: content,
          );
        }

        return content;
      },
    );
  }
}

class _CenteredHorizontalCropClipper extends CustomClipper<Rect> {
  final double sideCropPx;

  const _CenteredHorizontalCropClipper({required this.sideCropPx});

  @override
  Rect getClip(Size size) {
    final left = sideCropPx.clamp(0.0, size.width / 2);
    final right = (size.width - sideCropPx).clamp(size.width / 2, size.width);
    return Rect.fromLTRB(left, 0, right, size.height);
  }

  @override
  bool shouldReclip(covariant _CenteredHorizontalCropClipper oldClipper) {
    return oldClipper.sideCropPx != sideCropPx;
  }
}

class _ComparisonGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const divisions = 8;
    for (int i = 1; i < divisions; i++) {
      final dx = size.width * (i / divisions);
      final dy = size.height * (i / divisions);
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ComparisonGridPainter oldDelegate) => false;
}

class _ProSpineAnglePainter extends CustomPainter {
  final pose.PoseFrame poseFrame;

  _ProSpineAnglePainter({required this.poseFrame});

  @override
  void paint(Canvas canvas, Size size) {
    Offset? kpNorm(String label) {
      final kp = poseFrame.getKeypoint(label);
      if (kp == null || kp.confidence < 0.1) return null;
      return Offset(kp.x, kp.y);
    }

    final hipL = kpNorm('left_hip');
    final hipR = kpNorm('right_hip');
    final shL = kpNorm('left_shoulder');
    final shR = kpNorm('right_shoulder');
    if (hipL == null || hipR == null || shL == null || shR == null) return;

    final hipMidNorm = Offset((hipL.dx + hipR.dx) / 2, (hipL.dy + hipR.dy) / 2);
    final shMidNorm = Offset((shL.dx + shR.dx) / 2, (shL.dy + shR.dy) / 2);

    final dx = shMidNorm.dx - hipMidNorm.dx;
    final dy = hipMidNorm.dy - shMidNorm.dy;
    if (dx == 0 && dy == 0) return;

    final angle = math.atan2(dx, dy);
    final spineAngleDeg = angle.abs() * 180 / math.pi;

    final hipMid = Offset(hipMidNorm.dx * size.width, hipMidNorm.dy * size.height);
    final length = size.height * 0.6;
    final end = Offset(
      hipMid.dx + length * math.sin(angle),
      hipMid.dy - length * math.cos(angle),
    );

    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawLine(hipMid, end, paint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: '${spineAngleDeg.toStringAsFixed(1)}°',
        style: const TextStyle(
          color: Colors.red,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, end + const Offset(6, -6));
  }

  @override
  bool shouldRepaint(covariant _ProSpineAnglePainter oldDelegate) {
    return oldDelegate.poseFrame != poseFrame;
  }
}
