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
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (kDebugMode) {
      debugPrint('ANALYSIS_START analyzeVideo path=$videoPath timeout=${timeout.inSeconds}s');
    }
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

    if (kDebugMode) {
      debugPrint('ANALYSIS_DONE analyzeVideo frames=${frames.length} path=$videoPath');
    }

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
    bool dialogVisible = false;
    OverlayEntry? overlayEntry;
    VideoPlayerController? tempController;
    late final NavigatorState rootNavigator;
    late final OverlayState overlayState;

    final startedAt = DateTime.now();
    try {
      if (kDebugMode) {
        debugPrint('ANALYSIS_START runMoveNet path=$videoPath showDialog=$showProgressDialog');
      }
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
        ).whenComplete(() {
          dialogVisible = false;
        });
        dialogShown = true;
        dialogVisible = true;
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

      final totalMs = duration.inMilliseconds;
      const analysisFps = 60;
      int analyzedFrameIndex = 0;
      double currentMs = 0;

      while (currentMs < totalMs) {
        if (DateTime.now().difference(startedAt) > timeout) {
          throw TimeoutException('MoveNet analysis exceeded $timeout');
        }

        const int fpsUsed = analysisFps;
        final int currentFrameMs = currentMs.round();
        if (currentFrameMs >= totalMs) break;

        await tempController.seekTo(Duration(milliseconds: currentFrameMs));
        await Future.delayed(const Duration(milliseconds: 50));

        final boundary = repaintKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        if (boundary == null) {
          currentMs += 1000 / fpsUsed;
          continue;
        }

        final image = await boundary.toImage(pixelRatio: 1.0);
        ByteData? byteData;
        try {
          byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        } finally {
          image.dispose();
        }
        if (byteData == null) {
          currentMs += 1000 / fpsUsed;
          continue;
        }

        final rgba = byteData.buffer.asUint8List();
        final result = await MoveNetManager.analyzePoseFromRGBA(
          rgba,
          videoWidth,
          videoHeight,
        );

        if (result != null && result['keypoints'] != null) {
          final keypoints = result['keypoints'] as Map<String, dynamic>;
          final bodyPresent = PoseValidator.isBodyPresent(keypoints);
          final frameValid =
              bodyPresent && PoseValidator.isKeypointsValid(keypoints);
          final quality = PoseValidator.calculatePoseQuality(keypoints);

          if (frameValid) {
            poseData.add({
              'timestamp_ms': currentFrameMs,
              'frame_index': analyzedFrameIndex,
              'fps_used': fpsUsed,
              'keypoints': keypoints,
              'quality_score': quality,
              'frame_valid': frameValid,
            });
          }
        }

        if (kDebugMode && analyzedFrameIndex % 30 == 0) {
          debugPrint(
            'Analyzing frame #$analyzedFrameIndex at ${fpsUsed}fps',
          );
        }

        analyzedFrameIndex++;
        currentMs += 1000 / fpsUsed;
      }

      if (poseData.isEmpty) {
        throw Exception('No valid pose frames detected');
      }

      if (kDebugMode) {
        _logKeypointContinuityStats(poseData, tag: 'before_repair');
      }
      _enforceKeypointContinuity(poseData);
      if (kDebugMode) {
        _logKeypointContinuityStats(poseData, tag: 'after_repair');
      }

      final jsonPath = _poseJsonPath(videoPath);
      await File(jsonPath).writeAsString(jsonEncode({
        'model': 'MoveNet Lightning',
        'analyzed_at': DateTime.now().toIso8601String(),
        'frame_count': poseData.length,
        'analysis_method': 'overlay_simple',
        'frames': poseData,
      }));

      if (kDebugMode) {
        debugPrint('ANALYSIS_SAVED runMoveNet frames=${poseData.length} json=$jsonPath');
      }
    } finally {
      overlayEntry?.remove();
      await tempController?.dispose();
      if (dialogShown && dialogVisible) {
        rootNavigator.maybePop();
      }
    }
  }

  String _poseJsonPath(String videoPath) {
    final mp4Suffix = RegExp(r'\.mp4$', caseSensitive: false);
    if (mp4Suffix.hasMatch(videoPath)) {
      return videoPath.replaceFirst(mp4Suffix, '_movenet_pose.json');
    }
    return '${videoPath}_movenet_pose.json';
  }

  String _swingIdFromPath(String videoPath) {
    final fileName = videoPath.split(Platform.pathSeparator).last;
    return fileName.replaceAll('.mp4', '');
  }

  void _enforceKeypointContinuity(List<Map<String, dynamic>> frames) {
    if (frames.isEmpty) return;

    const minVisibleScore = PoseValidator.minKeypointConfidence;
    const continuityScore = 0.22;
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

    for (final name in keypointNames) {
      int? firstVisible;
      int? lastVisible;

      for (int i = 0; i < frames.length; i++) {
        final keypoints = frames[i]['keypoints'] as Map<String, dynamic>?;
        final kp = keypoints?[name] as Map<String, dynamic>?;
        final score = (kp?['score'] as num?)?.toDouble() ?? 0.0;
        if (score >= minVisibleScore) {
          firstVisible ??= i;
          lastVisible = i;
        }
      }

      if (firstVisible == null ||
          lastVisible == null ||
          firstVisible == lastVisible) {
        continue;
      }

      int repaired = 0;

      for (int i = firstVisible; i < frames.length; i++) {
        final keypoints = frames[i]['keypoints'] as Map<String, dynamic>?;
        if (keypoints == null) continue;

        final current = keypoints[name] as Map<String, dynamic>?;
        final currentScore = (current?['score'] as num?)?.toDouble() ?? 0.0;
        if (currentScore >= minVisibleScore) continue;

        int? prevIdx;
        for (int p = i - 1; p >= firstVisible; p--) {
          final prevKps = frames[p]['keypoints'] as Map<String, dynamic>?;
          final prev = prevKps?[name] as Map<String, dynamic>?;
          final prevScore = (prev?['score'] as num?)?.toDouble() ?? 0.0;
          if (prev != null && prevScore >= minVisibleScore) {
            prevIdx = p;
            break;
          }
        }

        int? nextIdx;
        for (int n = i + 1; n < frames.length; n++) {
          final nextKps = frames[n]['keypoints'] as Map<String, dynamic>?;
          final next = nextKps?[name] as Map<String, dynamic>?;
          final nextScore = (next?['score'] as num?)?.toDouble() ?? 0.0;
          if (next != null && nextScore >= minVisibleScore) {
            nextIdx = n;
            break;
          }
        }

        if (prevIdx == null && nextIdx == null) continue;

        double x;
        double y;
        double repairedScore;

        if (prevIdx != null && nextIdx != null) {
          final prevKp = (frames[prevIdx]['keypoints']
              as Map<String, dynamic>)[name] as Map<String, dynamic>;
          final nextKp = (frames[nextIdx]['keypoints']
              as Map<String, dynamic>)[name] as Map<String, dynamic>;

          final span = (nextIdx - prevIdx).toDouble();
          final t = ((i - prevIdx) / span).clamp(0.0, 1.0);
          final prevX = (prevKp['x'] as num).toDouble();
          final prevY = (prevKp['y'] as num).toDouble();
          final nextX = (nextKp['x'] as num).toDouble();
          final nextY = (nextKp['y'] as num).toDouble();
          x = prevX + (nextX - prevX) * t;
          y = prevY + (nextY - prevY) * t;

          final prevScore = (prevKp['score'] as num).toDouble();
          final nextScore = (nextKp['score'] as num).toDouble();
          repairedScore = ((prevScore + nextScore) * 0.5 * 0.85)
              .clamp(continuityScore, 1.0);
        } else if (prevIdx != null) {
          final prevKp = (frames[prevIdx]['keypoints']
              as Map<String, dynamic>)[name] as Map<String, dynamic>;
          x = (prevKp['x'] as num).toDouble();
          y = (prevKp['y'] as num).toDouble();
          repairedScore = ((prevKp['score'] as num).toDouble() * 0.85)
              .clamp(continuityScore, 1.0);
        } else {
          final nextKp = (frames[nextIdx!]['keypoints']
              as Map<String, dynamic>)[name] as Map<String, dynamic>;
          x = (nextKp['x'] as num).toDouble();
          y = (nextKp['y'] as num).toDouble();
          repairedScore = ((nextKp['score'] as num).toDouble() * 0.85)
              .clamp(continuityScore, 1.0);
        }

        keypoints[name] = {
          'x': x,
          'y': y,
          'score': repairedScore,
        };
        repaired++;
      }

      if (kDebugMode && repaired > 0) {
        debugPrint('Continuity repair for $name: $repaired frames');
      }
    }
  }

  void _logKeypointContinuityStats(
    List<Map<String, dynamic>> frames, {
    required String tag,
  }) {
    const minVisibleScore = PoseValidator.minKeypointConfidence;
    const keypointNames = [
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
    ];

    for (final name in keypointNames) {
      int? firstVisible;
      int visibleCount = 0;
      int missingAfterFirst = 0;

      for (int i = 0; i < frames.length; i++) {
        final keypoints = frames[i]['keypoints'] as Map<String, dynamic>?;
        final kp = keypoints?[name] as Map<String, dynamic>?;
        final score = (kp?['score'] as num?)?.toDouble() ?? 0.0;
        final visible = score >= minVisibleScore;

        if (visible) {
          firstVisible ??= i;
          visibleCount++;
        } else if (firstVisible != null) {
          missingAfterFirst++;
        }
      }

      if (firstVisible != null) {
        debugPrint(
            'Continuity[$tag] $name: visible=$visibleCount missing_after_first=$missingAfterFirst first=$firstVisible total=${frames.length}');
      }
    }
  }
}
