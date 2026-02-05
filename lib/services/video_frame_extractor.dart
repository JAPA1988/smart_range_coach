import 'dart:io';
import 'dart:typed_data';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui' as ui;

class VideoFrameExtractor {
  static Future<List<Uint8List>> extractFrames(
    String videoPath,
    int targetFps,
  ) async {
    final frames = <Uint8List>[];

    try {
      // Temp-Ordner für Frames
      final tempDir = await getTemporaryDirectory();
      final frameDir = Directory(
          '${tempDir.path}/frames_${DateTime.now().millisecondsSinceEpoch}');
      await frameDir.create(recursive: true);

      // FFmpeg-Command: Extrahiere Frames
      final outputPattern = '${frameDir.path}/frame_%04d.jpg';
      final command =
          '-i "$videoPath" -vf "fps=$targetFps,scale=256:256" "$outputPattern"';

      if (kDebugMode) {
        debugPrint('🎬 Extracting frames with FFmpeg: $targetFps fps');
      }

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (!ReturnCode.isSuccess(returnCode)) {
        if (kDebugMode) {
          debugPrint('⚠️ FFmpeg failed: ${await session.getOutput()}');
        }
        return frames;
      }

      // Lade alle extrahierten Frames
      final frameFiles = frameDir.listSync()
        ..sort((a, b) => a.path.compareTo(b.path));

      for (final file in frameFiles) {
        if (file is File && file.path.endsWith('.jpg')) {
          final bytes = await file.readAsBytes();

          // Konvertiere zu RGBA (MoveNet braucht das)
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          final byteData =
              await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);

          if (byteData != null) {
            frames.add(byteData.buffer.asUint8List());
          }

          frame.image.dispose();
          codec.dispose();
        }
      }

      // Cleanup
      await frameDir.delete(recursive: true);

      if (kDebugMode) debugPrint('✅ Extracted ${frames.length} frames');
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Frame extraction error: $e');
    }

    return frames;
  }
}
