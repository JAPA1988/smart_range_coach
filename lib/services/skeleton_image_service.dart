import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/user_swing.dart';
import '../widgets/skeleton_painter.dart';

class SkeletonImageService {
  Future<String> generateSkeletonImage(
    String swingId,
    String positionName,
    Map<String, Keypoint> keypoints,
  ) async {
    const width = 600.0;
    const height = 800.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, width, height),
      Paint()..color = Colors.black,
    );

    final painter = SkeletonPainter(
      keypoints: keypoints,
      showLabels: false,
    );
    painter.paint(canvas, const Size(width, height));

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception('Failed to render skeleton image');
    }
    final bytes = byteData.buffer.asUint8List();

    final directory = await getApplicationDocumentsDirectory();
    final swingDir = Directory('${directory.path}/swings/$swingId');
    if (!await swingDir.exists()) {
      await swingDir.create(recursive: true);
    }

    final filePath = '${swingDir.path}/$positionName.png';
    final file = File(filePath);
    await file.writeAsBytes(bytes);

    return filePath;
  }
}
