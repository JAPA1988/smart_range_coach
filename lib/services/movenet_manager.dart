import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

class MoveNetManager {
  static tfl.Interpreter? interpreter;

  static Future<void> init() async {
    if (interpreter != null) return;

    final options = tfl.InterpreterOptions()
      ..threads = 4
      ..useNnApiForAndroid = true;

    final candidates = [
      'movenet_singlepose_lightning.tflite',
      'assets/movenet_singlepose_lightning.tflite',
    ];
    for (final name in candidates) {
      try {
        interpreter = await Future.value(
          tfl.Interpreter.fromAsset(name, options: options),
        );
        if (interpreter != null) {
          if (kDebugMode) {
            debugPrint('MoveNet: model loaded from asset: $name');
          }
          break;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('MoveNet load attempt failed for $name: $e');
      }
    }

    if (interpreter == null) {
      try {
        final docDir = await getApplicationDocumentsDirectory();
        final candidate = File(
          '${docDir.path}${Platform.pathSeparator}smart_range_coach${Platform.pathSeparator}movenet_singlepose_lightning.tflite',
        );
        if (await candidate.exists()) {
          try {
            final localOptions = tfl.InterpreterOptions()..threads = 4;
            interpreter = await Future.value(
              tfl.Interpreter.fromFile(candidate, options: localOptions),
            );
            if (kDebugMode) {
              debugPrint('MoveNet: model loaded from file: ${candidate.path}');
            }
          } catch (e) {
            if (kDebugMode) debugPrint('MoveNet load from file failed: $e');
          }
        } else {
          if (kDebugMode) {
            debugPrint(
              'MoveNet: no model loaded. Place movenet_singlepose_lightning.tflite into assets or Documents/smart_range_coach.',
            );
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('MoveNet load: error checking Documents folder: $e');
        }
      }
    }
  }

  static Future<void> close() async {
    try {
      interpreter?.close();
    } catch (_) {}
    interpreter = null;
  }

  static Future<Map<String, dynamic>?> analyzePoseFromRGBA(
    Uint8List rgba,
    int width,
    int height,
  ) async {
    if (interpreter == null) return null;

    try {
      final input = Uint8List(192 * 192 * 3);
      int idx = 0;

      for (int y = 0; y < 192; y++) {
        for (int x = 0; x < 192; x++) {
          final srcX = (x * width / 192).floor();
          final srcY = (y * height / 192).floor();
          final srcIdx = (srcY * width + srcX) * 4;

          input[idx++] = rgba[srcIdx];
          input[idx++] = rgba[srcIdx + 1];
          input[idx++] = rgba[srcIdx + 2];
        }
      }

      final inputReshaped =
          input.buffer.asUint8List().reshape([1, 192, 192, 3]);
      final output = List.generate(
        1,
        (_) => List.generate(
          1,
          (_) => List.generate(17, (_) => List.filled(3, 0.0)),
        ),
      );

      interpreter!.run(inputReshaped, output);

      const keypointNames = [
        'nose',
        'left_eye',
        'right_eye',
        'left_ear',
        'right_ear',
        'left_shoulder',
        'right_shoulder',
        'left_elbow',
        'right_elbow',
        'left_wrist',
        'right_wrist',
        'left_hip',
        'right_hip',
        'left_knee',
        'right_knee',
        'left_ankle',
        'right_ankle',
      ];

      final keypoints = <String, Map<String, double>>{};
      final rawOut = output[0][0];

      for (int i = 0; i < 17; i++) {
        final y = (rawOut[i][0] as double).clamp(0.0, 1.0);
        final x = (rawOut[i][1] as double).clamp(0.0, 1.0);
        final score = (rawOut[i][2] as double).clamp(0.0, 1.0);

        final keypointName = keypointNames[i];
        if (keypointName == 'left_eye' || keypointName == 'right_eye') {
          continue;
        }

        keypoints[keypointName] = {
          'x': x,
          'y': y,
          'score': score,
        };
      }

      return {'keypoints': keypoints};
    } catch (e) {
      if (kDebugMode) debugPrint('MoveNet analysis failed: $e');
      return null;
    }
  }
}
