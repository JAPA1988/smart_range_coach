import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:video_player/video_player.dart';

import '../models/pose_validator.dart';
import '../models/user_swing.dart';
import 'movenet_manager.dart';

class VideoAnalysisService {
  Future<UserSwing> analyzeVideo(
    String videoPath, {
    BuildContext? context,
    bool showProgressDialog = true,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    if (context != null) {
      await _runMoveNetAnalysis(
        context,
        videoPath,
        showProgressDialog: showProgressDialog,
        timeout: timeout,
      );
    }

    final poseJsonPath = _poseJsonPath(videoPath);
    final poseFile = File(poseJsonPath);

    if (!await poseFile.exists()) {
      throw Exception('Pose data not found at $poseJsonPath');
    }

    final jsonString = await poseFile.readAsString();
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    final framesJson = List<Map<String, dynamic>>.from(data['frames'] ?? []);

    final frames = framesJson.map(FrameData.fromJson).toList();

    return UserSwing(
      id: _swingIdFromPath(videoPath),
      videoPath: videoPath,
      recordedAt: DateTime.now(),
      frames: frames,
      status:
          frames.isNotEmpty ? AnalysisStatus.completed : AnalysisStatus.failed,
    );
  }

  Future<void> _runMoveNetAnalysis(
    BuildContext context,
    String videoPath, {
    required bool showProgressDialog,
    required Duration timeout,
  }) async {
    bool dialogShown = false;
    OverlayEntry? overlayEntry;
    VideoPlayerController? tempController;
    late final NavigatorState rootNavigator;
    late final OverlayState overlayState;

    final startedAt = DateTime.now();
    try {
      rootNavigator = Navigator.of(context, rootNavigator: true);
      final overlay = Overlay.maybeOf(context);
      if (overlay == null) {
        throw Exception('No Overlay found in the provided context');
      }
      overlayState = overlay;

      if (showProgressDialog) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Analyzing swing with MoveNet...'),
              ],
            ),
          ),
        );
        dialogShown = true;
      }

      await MoveNetManager.init().timeout(const Duration(seconds: 20));
      if (MoveNetManager.interpreter == null) {
        throw Exception('MoveNet could not be loaded');
      }

      tempController = VideoPlayerController.file(File(videoPath));
      await tempController.initialize().timeout(const Duration(seconds: 20));
      await tempController.pause();

      final duration = tempController.value.duration;
      final videoWidth = tempController.value.size.width.toInt();
      final videoHeight = tempController.value.size.height.toInt();

      final repaintKey = GlobalKey();
      overlayEntry = OverlayEntry(
        builder: (_) => Positioned(
          left: -10000,
          top: -10000,
          child: RepaintBoundary(
            key: repaintKey,
            child: SizedBox(
              width: videoWidth.toDouble(),
              height: videoHeight.toDouble(),
              child: VideoPlayer(tempController!),
            ),
          ),
        ),
      );
      overlayState.insert(overlayEntry);
      await Future.delayed(const Duration(milliseconds: 400));

      final poseData = <Map<String, dynamic>>[];

      const estimatedFps = 15;
      final frameIntervalMs = (1000 / estimatedFps).round();
      final totalMs = duration.inMilliseconds;
      final totalFrames = (totalMs / frameIntervalMs).ceil();

      for (int frameIndex = 0; frameIndex < totalFrames; frameIndex++) {
        if (DateTime.now().difference(startedAt) > timeout) {
          throw TimeoutException('MoveNet analysis exceeded $timeout');
        }
        final currentMs = frameIndex * frameIntervalMs;
        if (currentMs >= totalMs) break;

        await tempController.seekTo(Duration(milliseconds: currentMs));
        await Future.delayed(const Duration(milliseconds: 50));

        final boundary = repaintKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        if (boundary == null) continue;

        final image = await boundary.toImage(pixelRatio: 1.0);
        final byteData =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (byteData == null) continue;

        final rgba = byteData.buffer.asUint8List();
        final result = await MoveNetManager.analyzePoseFromRGBA(
          rgba,
          videoWidth,
          videoHeight,
        );

        if (result != null && result['keypoints'] != null) {
          final keypoints = result['keypoints'] as Map<String, dynamic>;
          if (PoseValidator.isKeypointsValid(keypoints)) {
            final quality = PoseValidator.calculatePoseQuality(keypoints);
            poseData.add({
              'timestamp_ms': currentMs,
              'frame_index': frameIndex,
              'fps_used': estimatedFps,
              'keypoints': keypoints,
              'quality_score': quality,
            });
          }
        }

        if (kDebugMode && frameIndex % 30 == 0) {
          debugPrint(
            'Analyzing frame $frameIndex/$totalFrames',
          );
        }
      }

      if (poseData.isEmpty) {
        throw Exception('No valid pose frames detected');
      }

      final jsonPath = _poseJsonPath(videoPath);
      await File(jsonPath).writeAsString(jsonEncode({
        'model': 'MoveNet Lightning',
        'analyzed_at': DateTime.now().toIso8601String(),
        'frame_count': poseData.length,
        'analysis_method': 'overlay_simple',
        'frames': poseData,
      }));
    } finally {
      overlayEntry?.remove();
      await tempController?.dispose();
      if (dialogShown) {
        rootNavigator.maybePop();
      }
    }
  }

  String _poseJsonPath(String videoPath) {
    if (videoPath.toLowerCase().endsWith('.mp4')) {
      return videoPath.replaceAll('.mp4', '_movenet_pose.json');
    }
    return '${videoPath}_movenet_pose.json';
  }

  String _swingIdFromPath(String videoPath) {
    final fileName = videoPath.split(Platform.pathSeparator).last;
    return fileName.replaceAll('.mp4', '');
  }
}
