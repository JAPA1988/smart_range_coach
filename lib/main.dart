import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:async';
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;
import 'package:flutter/foundation.dart';

// Services
import 'services/swing_comparison.dart';
import 'screens/swing_comparison_screen.dart';

// Golf-Schwung-Phasen
enum SwingPhase {
  address, // Setup
  takeaway, // Schwung beginnt
  backswing, // Rückschwung
  top, // Höchster Punkt
  transition, // Übergang
  downswing, // Abschwung - SCHNELL!
  impact, // Ball-Kontakt - KRITISCH!
  followThrough, // Durchschwung
  finish, // Ende
}

// Motion-Segment für adaptive Analyse
class MotionSegment {
  final int startMs;
  final int endMs;
  final double motionLevel;
  final SwingPhase phase;
  final int recommendedFps;

  MotionSegment({
    required this.startMs,
    required this.endMs,
    required this.motionLevel,
    required this.phase,
    required this.recommendedFps,
  });

  Map<String, dynamic> toJson() => {
        'start_ms': startMs,
        'end_ms': endMs,
        'motion_level': motionLevel,
        'phase': phase.toString(),
        'fps': recommendedFps,
      };
}

// Latency Compensator für Predictive Leading
class LatencyCompensator {
  final List<int> _latencySamples = [];
  int _averageLatency = 60; // Start-Wert

  void measureLatency(int videoTime, int renderTime) {
    final latency = renderTime - videoTime;
    if (latency > 0 && latency < 200) {
      // Nur sinnvolle Werte
      _latencySamples.add(latency);

      if (_latencySamples.length > 20) {
        _latencySamples.removeAt(0);
      }

      _averageLatency =
          _latencySamples.reduce((a, b) => a + b) ~/ _latencySamples.length;
    }
  }

  int getCompensatedTime(int currentTime) {
    return currentTime + _averageLatency;
  }

  int get averageLatency => _averageLatency;
}

// Simple singleton manager for MoveNet interpreter so it can be initialized from
// different screens (camera recording start or review screen) without duplicating code.
class MoveNetManager {
  static tfl.Interpreter? interpreter;
  static Future<void> init() async {
    if (interpreter != null) return;

    // TFLite-Optionen: GPU + NNAPI für maximale Performance
    final options = tfl.InterpreterOptions()
      ..threads = 4
      ..useNnApiForAndroid = true; // Android Neural Networks API

    final candidates = [
      'movenet_singlepose_lightning.tflite',
      'assets/movenet_singlepose_lightning.tflite',
    ];
    for (final name in candidates) {
      try {
        interpreter = await Future.value(
            tfl.Interpreter.fromAsset(name, options: options));
        if (interpreter != null) {
          if (kDebugMode) debugPrint('MoveNet: model loaded from asset: $name');
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
            '${docDir.path}${Platform.pathSeparator}smart_range_coach${Platform.pathSeparator}movenet_singlepose_lightning.tflite');
        if (await candidate.exists()) {
          try {
            final options = tfl.InterpreterOptions()..threads = 4;
            interpreter = await Future.value(
                tfl.Interpreter.fromFile(candidate, options: options));
            if (kDebugMode)
              debugPrint('MoveNet: model loaded from file: ${candidate.path}');
          } catch (e) {
            if (kDebugMode) debugPrint('MoveNet load from file failed: $e');
          }
        } else {
          if (kDebugMode)
            debugPrint(
                'MoveNet: no model loaded. Place movenet_singlepose_lightning.tflite into assets or Documents/smart_range_coach.');
        }
      } catch (e) {
        if (kDebugMode)
          debugPrint('MoveNet load: error checking Documents folder: $e');
      }
    }
  }

  static Future<void> close() async {
    try {
      interpreter?.close();
    } catch (_) {}
    interpreter = null;
  }
}

// Small set of issues for the review checklist.
enum Issue {
  addressSpineTooUpright,
  addressShouldersOpen,
  swingLossOfPosture,
  impactFlipRelease,
}

String issueTitle(Issue i) {
  switch (i) {
    case Issue.addressSpineTooUpright:
      return 'Address: Rücken zu aufrecht';
    case Issue.addressShouldersOpen:
      return 'Address: Schultern offen';
    case Issue.swingLossOfPosture:
      return 'Swing: Verlust der Haltung';
    case Issue.impactFlipRelease:
      return 'Impact: Flip/zu frühe Handrotation';
  }
}

// Simple detected line model (normalized coordinates 0..1)
// p1/p2 are relative to image width/height (0..1)
// label e.g. 'shoulder', 'spine', 'shaft'
// color optional
class DetectedLine {
  final Offset p1;
  final Offset p2;
  final String label;
  final Color color;
  DetectedLine(
      {required this.p1,
      required this.p2,
      required this.label,
      required this.color});
}

class LinesPainter extends CustomPainter {
  final List<DetectedLine> lines;
  LinesPainter({required this.lines});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;
    for (final line in lines) {
      paint.color = line.color;
      final p1 = Offset(line.p1.dx * size.width, line.p1.dy * size.height);
      final p2 = Offset(line.p2.dx * size.width, line.p2.dy * size.height);
      canvas.drawLine(p1, p2, paint);
      final tp = TextPainter(
          text: TextSpan(
              text: line.label,
              style: TextStyle(color: line.color, fontSize: 12)),
          textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, p1 + const Offset(6, -16));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Painter for MoveNet keypoints
class KeypointsPainter extends CustomPainter {
  final List<Map<String, double>> keypoints;
  final double minScore;
  final Size?
      imageSize; // captured image pixel size used to map normalized coords to canvas
  KeypointsPainter(
      {required this.keypoints, required this.minScore, this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final tpStyle = const TextStyle(color: Colors.white, fontSize: 10);
    for (int i = 0; i < keypoints.length; i++) {
      final kp = keypoints[i];
      final score = kp['score'] ?? 0.0;
      if (score < minScore) continue;
      double dx, dy;
      if (imageSize != null) {
        final double sx = size.width / imageSize!.width;
        final double sy = size.height / imageSize!.height;
        final double px = (kp['x'] ?? 0.0) * imageSize!.width;
        final double py = (kp['y'] ?? 0.0) * imageSize!.height;
        dx = px * sx;
        dy = py * sy;
      } else {
        dx = (kp['x'] ?? 0.0) * size.width;
        dy = (kp['y'] ?? 0.0) * size.height;
      }
      paint.color =
          Colors.primaries[i % Colors.primaries.length].withAlpha(200);
      canvas.drawCircle(Offset(dx, dy), 6.0, paint);
      final tp = TextPainter(
          text:
              TextSpan(text: '$i:${score.toStringAsFixed(2)}', style: tpStyle),
          textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(dx + 6, dy - 6));
    }
  }

  @override
  bool shouldRepaint(covariant KeypointsPainter oldDelegate) => true;
}

// Painter to draw the last preprocessing crop rectangle (debugging)
class _CropPainter extends CustomPainter {
  final Map<String, int> crop;
  final Size imageSize;
  _CropPainter({required this.crop, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.redAccent
      ..strokeWidth = 2.0;
    // crop coords are in image pixels; we map them to canvas size
    final double sx = size.width / imageSize.width;
    final double sy = size.height / imageSize.height;
    final Rect r = Rect.fromLTWH(
        crop['x']! * sx, crop['y']! * sy, crop['w']! * sx, crop['h']! * sy);
    canvas.drawRect(r, paint);
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) =>
      old.crop != crop || old.imageSize != imageSize;
}

// Painter für alle relevanten Golf-Keypoints
class _PoseKeyPointsPainter extends CustomPainter {
  final Map<String, Offset?>? keypoints;
  final Size? imageSize;

  _PoseKeyPointsPainter({this.keypoints, this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    if (keypoints == null || imageSize == null) return;

    final double sx = size.width / imageSize!.width;
    final double sy = size.height / imageSize!.height;

    // Definiere Keypoint-Farben (Golf-relevant)
    final keypointColors = {
      'left_shoulder': Colors.red,
      'right_shoulder': Colors.red,
      'left_elbow': Colors.orange,
      'right_elbow': Colors.orange,
      'left_wrist': Colors.yellow,
      'right_wrist': Colors.yellow,
      'left_hip': Colors.green,
      'right_hip': Colors.green,
      'left_knee': Colors.blue,
      'right_knee': Colors.blue,
    };

    // Zeichne jeden Keypoint
    keypointColors.forEach((name, color) {
      final point = keypoints![name];
      if (point != null) {
        final dx = point.dx * sx;
        final dy = point.dy * sy;

        // Äußerer weißer Ring
        final strokePaint = Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white
          ..strokeWidth = 2.0;
        canvas.drawCircle(Offset(dx, dy), 8, strokePaint);

        // Innerer farbiger Punkt
        final fillPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = color;
        canvas.drawCircle(Offset(dx, dy), 6, fillPaint);
      }
    });

    // Zeichne Verbindungslinien (Skeleton)
    _drawLine(canvas, 'left_shoulder', 'right_shoulder',
        Colors.red.withOpacity(0.5), sx, sy);
    _drawLine(canvas, 'left_shoulder', 'left_elbow',
        Colors.red.withOpacity(0.5), sx, sy);
    _drawLine(canvas, 'right_shoulder', 'right_elbow',
        Colors.red.withOpacity(0.5), sx, sy);
    _drawLine(canvas, 'left_elbow', 'left_wrist',
        Colors.orange.withOpacity(0.5), sx, sy);
    _drawLine(canvas, 'right_elbow', 'right_wrist',
        Colors.orange.withOpacity(0.5), sx, sy);
    _drawLine(
        canvas, 'left_hip', 'right_hip', Colors.green.withOpacity(0.5), sx, sy);
    _drawLine(canvas, 'left_shoulder', 'left_hip', Colors.cyan.withOpacity(0.5),
        sx, sy);
    _drawLine(canvas, 'right_shoulder', 'right_hip',
        Colors.cyan.withOpacity(0.5), sx, sy);
    _drawLine(
        canvas, 'left_hip', 'left_knee', Colors.green.withOpacity(0.5), sx, sy);
    _drawLine(canvas, 'right_hip', 'right_knee', Colors.green.withOpacity(0.5),
        sx, sy);
  }

  void _drawLine(Canvas canvas, String from, String to, Color color, double sx,
      double sy) {
    final p1 = keypoints![from];
    final p2 = keypoints![to];

    if (p1 != null && p2 != null) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke;

      canvas.drawLine(
        Offset(p1.dx * sx, p1.dy * sy),
        Offset(p2.dx * sx, p2.dy * sy),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PoseKeyPointsPainter old) =>
      old.keypoints != keypoints || old.imageSize != imageSize;
}

// Top-level isolate helper: center-crop -> bilinear resize -> normalize
// Receives a Map with keys: 'rgba' (Uint8List), 'w', 'h', 'size'
// Returns a Map with keys:
//  - 'image': nested List [size][size][3] with doubles in 0..1 (normalized, the model input)
//  - 'crop': { 'x': int, 'y': int, 'w': int, 'h': int } describing the crop in original pixels
Future<Map<String, dynamic>> _resizeNormalize(Map<String, dynamic> args) async {
  final Uint8List rgba = args['rgba'];
  final int w = args['w'];
  final int h = args['h'];
  final int size = args['size'];

  // compute centered square crop to preserve aspect ratio as MoveNet expects square input
  final int cropSide = math.min(w, h);
  final int cropX = ((w - cropSide) / 2).floor();
  final int cropY = ((h - cropSide) / 2).floor();
  final int cropW = cropSide;
  final int cropH = cropSide;

  List<List<List<double>>> out = List.generate(
      size, (_) => List.generate(size, (_) => List.filled(3, 0.0)));

  final double xScale = cropW / size;
  final double yScale = cropH / size;

  for (int ty = 0; ty < size; ty++) {
    final double fy = (ty + 0.5) * yScale - 0.5;
    final int syf = fy.floor();
    final int y0 = (cropY + syf).clamp(0, h - 1);
    final int y1 = (y0 + 1).clamp(0, h - 1);
    final double wy = fy - syf;
    for (int tx = 0; tx < size; tx++) {
      final double fx = (tx + 0.5) * xScale - 0.5;
      final int sxf = fx.floor();
      final int x0 = (cropX + sxf).clamp(0, w - 1);
      final int x1 = (x0 + 1).clamp(0, w - 1);
      final double wx = fx - sxf;

      for (int c = 0; c < 3; c++) {
        final int idx00 = (y0 * w + x0) * 4 + c;
        final int idx10 = (y0 * w + x1) * 4 + c;
        final int idx01 = (y1 * w + x0) * 4 + c;
        final int idx11 = (y1 * w + x1) * 4 + c;
        final double v00 = (rgba[idx00] & 0xFF) / 255.0;
        final double v10 = (rgba[idx10] & 0xFF) / 255.0;
        final double v01 = (rgba[idx01] & 0xFF) / 255.0;
        final double v11 = (rgba[idx11] & 0xFF) / 255.0;

        final double v0 = v00 * (1 - wx) + v10 * wx;
        final double v1 = v01 * (1 - wx) + v11 * wx;
        final double v = v0 * (1 - wy) + v1 * wy;
        out[ty][tx][c] = v;
      }
    }
  }

  return {
    'image': out,
    'crop': {'x': cropX, 'y': cropY, 'w': cropW, 'h': cropH},
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CameraSmokeTestApp());
}

class CameraSmokeTestApp extends StatelessWidget {
  const CameraSmokeTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Range Coach – Camera Smoke Test',
      theme: ThemeData.dark(),
      builder: (context, child) {
        return SafeArea(
          child: child!,
        );
      },
      home: const CameraSmokeTestScreen(),
    );
  }
}

// Simple review screen demonstrating safe video loading and minimal controls.
class SwingQuickReviewScreen extends StatefulWidget {
  final String videoPath;
  final int swingNumber;

  const SwingQuickReviewScreen(
      {required this.videoPath, this.swingNumber = 1, super.key});

  @override
  State<SwingQuickReviewScreen> createState() => _SwingQuickReviewScreenState();
}

class _SwingQuickReviewScreenState extends State<SwingQuickReviewScreen> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _videoReady = false;
  String? _videoError;
  final Set<Issue> _selected = {};
  VoidCallback? _ctrlListener;
  final GlobalKey _videoRepaintKey = GlobalKey();

  // Detected overlay lines (in image coordinates)
  List<DetectedLine> _detectedLines = [];
  bool _analysisRunning = false;
  // MoveNet UI / export state
  bool _useMoveNet = true;
  double _minKeypointScore = 0.3;
  List<Map<String, double>>? _lastKeypoints;
  Map<String, int>? _lastCrop;
  bool _centerCropEnabled = true;
  // Shoulder tracking state (normalized coordinates 0..1)
  bool _autoTrackShoulders = true;
  // stored as pixel coordinates relative to last captured image
  Offset? _leftShoulderMarker;
  Offset? _rightShoulderMarker;
  Offset? _leftHipMarker;
  Offset? _rightHipMarker;
  Offset? _leftKneeMarker;
  Offset? _rightKneeMarker;
  Offset? _leftElbowMarker;
  Offset? _rightElbowMarker;
  // NEU: Alle Golf-Keypoints in einer Map
  Map<String, Offset?>? _allKeypoints;
  // Smoothing für flüssigere Bewegung
  final Map<String, Offset?> _smoothedKeypoints = {};
  final double _smoothingFactor =
      0.1; // 0 = keine Smoothing, 1 = maximales Smoothing (reduziert für schnellere Reaktion)

  // Latency Compensator für Predictive Leading
  final _latencyCompensator = LatencyCompensator();

  // Analysis Status für Dialog
  String _analysisStatus = 'Initialisiere...';
  String _analysisProgress = '';
  int _shoulderMissCount = 0;
  final int _maxShoulderMiss = 6; // hide after this many misses
  Timer? _shoulderTrackingTimer;
  final Duration _shoulderTrackInterval = const Duration(
      milliseconds:
          1000); // Erhöht von 300ms auf 1000ms für bessere Performance
  Size? _lastCapturedImageSize;

  // Frame-Skipping für Performance-Optimierung
  int _frameCounter = 0;
  bool _isProcessingFrame = false;

  // Vorberechnete Schulter-Positionen
  List<Map<String, dynamic>>? _precomputedShoulders;

  // Simple detected line model (normalized coordinates 0..1)
  // p1/p2 are relative to image width/height (0..1)
  // label e.g. 'shoulder', 'spine', 'shaft'
  // color optional

  // helper types

  @override
  void initState() {
    super.initState();
    _initVideo();
    _loadPrecomputedPose();
    // Attempt to load MoveNet model when this screen initializes (best-effort).
    MoveNetManager.init();
  }

  Future<void> _loadPrecomputedPose() async {
    try {
      // Versuche zuerst vollständige Pose-Daten zu laden
      final poseJsonPath =
          widget.videoPath.replaceAll('.mp4', '_movenet_pose.json');
      final poseFile = File(poseJsonPath);

      if (await poseFile.exists()) {
        final jsonString = await poseFile.readAsString();
        final data = jsonDecode(jsonString);
        _precomputedShoulders = List<Map<String, dynamic>>.from(data['frames']);

        if (kDebugMode)
          debugPrint(
              '✅ Loaded ${_precomputedShoulders!.length} pose frames (17 keypoints)');
      } else {
        // Fallback: Nur Schultern (alte JSON)
        final shoulderJsonPath =
            widget.videoPath.replaceAll('.mp4', '_shoulders.json');
        final shoulderFile = File(shoulderJsonPath);

        if (await shoulderFile.exists()) {
          final jsonString = await shoulderFile.readAsString();
          final data = jsonDecode(jsonString) as List;
          _precomputedShoulders =
              data.map((e) => e as Map<String, dynamic>).toList();

          if (kDebugMode)
            debugPrint(
                '✅ Loaded ${_precomputedShoulders!.length} shoulder positions (legacy)');
        } else {
          if (kDebugMode)
            debugPrint('ℹ️ No pre-computed data found, will use live tracking');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to load pre-computed data: $e');
    }
  }

  void _updateAllKeypointsFromPrecomputed() {
    if (_precomputedShoulders == null ||
        _controller == null ||
        _precomputedShoulders!.isEmpty) {
      if (kDebugMode) debugPrint('⚠️ No pose frames available');
      return;
    }

    final currentMs = _controller!.value.position.inMilliseconds;
    final renderStartTime = DateTime.now().millisecondsSinceEpoch;

    // ✨ PREDICTIVE LEADING: Kompensiere Render-Latenz
    final predictedMs = _latencyCompensator.getCompensatedTime(currentMs);

    // Debug nur alle 60 Frames
    _frameCounter++;
    if (kDebugMode && _frameCounter % 60 == 0) {
      debugPrint(
          '🎬 Current: ${currentMs}ms, Predicted: ${predictedMs}ms, Total frames: ${_precomputedShoulders!.length}');
    }

    final videoSize = _lastCapturedImageSize ??
        Size(_controller!.value.size.width, _controller!.value.size.height);

    // Finde die zwei nächsten Frames (vorher und nachher) für lineare Interpolation
    Map<String, dynamic>? frameBefore;
    Map<String, dynamic>? frameAfter;

    for (int i = 0; i < _precomputedShoulders!.length; i++) {
      final frame = _precomputedShoulders![i];
      final frameMs = frame['timestamp_ms'] as int;

      if (frameMs <= predictedMs) {
        frameBefore = frame;
      }
      if (frameMs >= predictedMs && frameAfter == null) {
        frameAfter = frame;
        break;
      }
    }

    // Wenn am Anfang: nutze ersten Frame
    if (predictedMs < (_precomputedShoulders!.first['timestamp_ms'] as int)) {
      if (kDebugMode && _frameCounter % 60 == 0) {
        debugPrint('⏮️ Using first frame');
      }
      frameBefore = _precomputedShoulders!.first;
      frameAfter = null;
    }

    // Wenn am Ende: nutze letzten Frame
    if (predictedMs > (_precomputedShoulders!.last['timestamp_ms'] as int)) {
      if (kDebugMode && _frameCounter % 60 == 0) {
        debugPrint('⏭️ Using last frame');
      }
      frameBefore = _precomputedShoulders!.last;
      frameAfter = null;
    }

    // Falls wir zwei Frames haben, interpoliere zwischen ihnen
    if (frameBefore != null && frameAfter != null) {
      final beforeMs = frameBefore['timestamp_ms'] as int;
      final afterMs = frameAfter['timestamp_ms'] as int;

      // Interpolationsfaktor (0.0 = frameBefore, 1.0 = frameAfter)
      // WICHTIG: Nutze predictedMs statt currentMs für bessere Synchronisation
      final double t;
      if (afterMs == beforeMs) {
        t = 0.0;
      } else {
        t = ((predictedMs - beforeMs) / (afterMs - beforeMs)).clamp(0.0, 1.0);
      }

      if (kDebugMode && _frameCounter % 60 == 0) {
        debugPrint(
            '🔄 Interpolating: ${beforeMs}ms -> ${afterMs}ms (t=${t.toStringAsFixed(2)})');
      }

      // Nutze Helper-Methode für saubere Interpolation
      final interpolatedKeypoints = _interpolateKeypoints(
        frameBefore: frameBefore,
        frameAfter: frameAfter,
        t: t,
        videoSize: videoSize,
      );

      // Wende Smoothing an (reduziert Jitter bei schnellen Bewegungen)
      _applySmoothingToKeypoints(interpolatedKeypoints);

      setState(() {
        _allKeypoints = _smoothedKeypoints.isNotEmpty
            ? Map.from(_smoothedKeypoints)
            : interpolatedKeypoints;
        _shoulderMissCount = 0;

        // Backward compatibility: Setze auch einzelne Marker
        _leftShoulderMarker = _allKeypoints!['left_shoulder'];
        _rightShoulderMarker = _allKeypoints!['right_shoulder'];
      });

      // Messe Latenz für adaptive Kompensation
      final renderEndTime = DateTime.now().millisecondsSinceEpoch;
      _latencyCompensator.measureLatency(currentMs, renderEndTime);
    } else if (frameBefore != null) {
      // Nur ein Frame vorhanden, nutze diesen direkt
      if (kDebugMode && _frameCounter % 60 == 0) {
        debugPrint('🎯 Exact match at ${frameBefore['timestamp_ms']}ms');
      }

      final keypoints = frameBefore['keypoints'];
      final interpolatedKeypoints = <String, Offset?>{};

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
        final kp = keypoints?[name];
        if (kp != null) {
          interpolatedKeypoints[name] = Offset(
            (kp['x'] as double) * videoSize.width,
            (kp['y'] as double) * videoSize.height,
          );
        }
      }

      setState(() {
        _allKeypoints = interpolatedKeypoints;
        _shoulderMissCount = 0;

        // Backward compatibility
        _leftShoulderMarker = interpolatedKeypoints['left_shoulder'];
        _rightShoulderMarker = interpolatedKeypoints['right_shoulder'];
      });
    } else {
      // Fallback: Finde nächsten verfügbaren Frame
      if (kDebugMode && _frameCounter % 60 == 0) {
        debugPrint('🔍 Fallback: Finding nearest frame');
      }

      Map<String, dynamic>? nearest;
      int minDiff = 999999;

      for (final frame in _precomputedShoulders!) {
        final frameMs = frame['timestamp_ms'] as int;
        final diff = (frameMs - predictedMs).abs();
        if (diff < minDiff) {
          minDiff = diff;
          nearest = frame;
        }
      }

      if (nearest != null) {
        final keypoints = nearest['keypoints'];
        final interpolatedKeypoints = <String, Offset?>{};

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
          final kp = keypoints?[name];
          if (kp != null) {
            interpolatedKeypoints[name] = Offset(
              (kp['x'] as double) * videoSize.width,
              (kp['y'] as double) * videoSize.height,
            );
          }
        }

        setState(() {
          _allKeypoints = interpolatedKeypoints;
          _shoulderMissCount = 0;
          _leftShoulderMarker = interpolatedKeypoints['left_shoulder'];
          _rightShoulderMarker = interpolatedKeypoints['right_shoulder'];
        });
      }
    }
  }

  /// Predictive Smoothing für flüssigere Bewegung
  void _applySmoothingToKeypoints(Map<String, Offset?> rawKeypoints) {
    rawKeypoints.forEach((name, newPos) {
      if (newPos != null) {
        final oldPos = _smoothedKeypoints[name];

        if (oldPos == null) {
          // Erster Frame: Keine Smoothing
          _smoothedKeypoints[name] = newPos;
        } else {
          // Exponential Moving Average (EMA)
          _smoothedKeypoints[name] = Offset(
            oldPos.dx * _smoothingFactor + newPos.dx * (1 - _smoothingFactor),
            oldPos.dy * _smoothingFactor + newPos.dy * (1 - _smoothingFactor),
          );
        }
      }
    });
  }

  /// Interpoliert zwischen zwei Keypoint-Sets basierend auf Faktor t (0.0 - 1.0)
  Map<String, Offset?> _interpolateKeypoints({
    required Map<String, dynamic> frameBefore,
    required Map<String, dynamic> frameAfter,
    required double t,
    required Size videoSize,
  }) {
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

    final interpolated = <String, Offset?>{};

    for (final name in keypointNames) {
      final beforeKp = frameBefore['keypoints']?[name];
      final afterKp = frameAfter['keypoints']?[name];

      if (beforeKp != null && afterKp != null) {
        // Lineare Interpolation: before * (1-t) + after * t
        final x =
            (beforeKp['x'] as double) * (1 - t) + (afterKp['x'] as double) * t;
        final y =
            (beforeKp['y'] as double) * (1 - t) + (afterKp['y'] as double) * t;

        interpolated[name] = Offset(x * videoSize.width, y * videoSize.height);
      }
    }

    return interpolated;
  }

  final int _movenetInputSize =
      192; // Lightning: 192x192 statt Thunder: 256x256

  Future<void> _initVideo() async {
    setState(() {
      _loading = true;
      _videoError = null;
      _videoReady = false;
    });

    VideoPlayerController? local;
    try {
      local = VideoPlayerController.file(File(widget.videoPath));
      await local.initialize();
      // Ensure no looping and don't autoplay
      await local.setLooping(false);
      await local.pause();
      await local.seekTo(Duration.zero);

      if (!mounted) {
        await local.dispose();
        return;
      }

      // Attach a listener so the UI updates when playback position/state changes
      _ctrlListener = () {
        // Debug logging to observe whether playback position advances.
        if (kDebugMode) {
          try {
            final v = local!.value;
            debugPrint(
                'VIDEO CTRL: isPlaying=${v.isPlaying} pos=${v.position.inMilliseconds}ms dur=${v.duration.inMilliseconds}ms');
          } catch (_) {}
        }

        // NEU: Verwende alle Keypoints falls verfügbar
        if (_precomputedShoulders != null) {
          _updateAllKeypointsFromPrecomputed();
        }

        if (mounted) {
          setState(() {});
        }
        // Manage shoulder tracking timer based on playback
        try {
          if (local != null && local.value.isPlaying && _autoTrackShoulders) {
            _ensureShoulderTimerRunning();
          } else {
            _stopShoulderTimer();
          }
        } catch (_) {}
      };
      local.addListener(_ctrlListener!);

      setState(() {
        _controller = local;
        _videoReady = true;
        _loading = false;
      });
    } catch (e) {
      try {
        await local?.dispose();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _controller = null;
        _loading = false;
        _videoReady = false;
        _videoError = 'Video konnte nicht geladen werden: $e';
      });
    }
  }

  @override
  void dispose() {
    // dispose MoveNet interpreter if created
    try {
      MoveNetManager.close();
    } catch (_) {}
    if (_controller != null && _ctrlListener != null) {
      try {
        _controller!.removeListener(_ctrlListener!);
      } catch (_) {}
    }
    _controller?.dispose();
    _stopShoulderTimer();
    super.dispose();
  }

  void _ensureShoulderTimerRunning() {
    // Nur starten wenn KEINE vorberechneten Daten vorhanden sind
    if (_precomputedShoulders != null) {
      if (kDebugMode)
        debugPrint('Using pre-computed shoulders, skipping live tracking');
      return;
    }

    if (_shoulderTrackingTimer != null && _shoulderTrackingTimer!.isActive)
      return;
    _shoulderTrackingTimer = Timer.periodic(_shoulderTrackInterval, (_) async {
      try {
        await _trackShouldersOnce();
      } catch (_) {}
    });
  }

  void _stopShoulderTimer() {
    try {
      _shoulderTrackingTimer?.cancel();
      _shoulderTrackingTimer = null;
    } catch (_) {}
  }

  Future<void> _trackShouldersOnce() async {
    // Frame-Skipping: Verarbeite nur jeden 5. Frame (80% weniger Last)
    _frameCounter++;
    if (_frameCounter % 5 != 0) return;

    // Überspringe, wenn noch ein Frame verarbeitet wird
    if (_isProcessingFrame) return;
    _isProcessingFrame = true;

    try {
      // lightweight sampling while video plays
      final renderObj = _videoRepaintKey.currentContext?.findRenderObject();
      if (renderObj is! RenderRepaintBoundary) return;
      final boundary = renderObj;
      final ui.Image captured = await boundary.toImage(pixelRatio: 1.0);
      final byteData =
          await captured.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return;
      final rgba = byteData.buffer.asUint8List();
      final w = captured.width;
      final h = captured.height;
      // remember captured image size for accurate mapping to canvas
      _lastCapturedImageSize = Size(w.toDouble(), h.toDouble());

      List<Map<String, double>>? kpRes;
      if (_useMoveNet && MoveNetManager.interpreter != null) {
        try {
          kpRes = await _runMoveNetOnRgba(rgba, w, h);
        } catch (_) {
          kpRes = null;
        }
      }

      if (kpRes != null && kpRes.length >= 13) {
        final l = kpRes[5];
        final r = kpRes[6];
        if ((l['score'] ?? 0.0) >= _minKeypointScore &&
            (r['score'] ?? 0.0) >= _minKeypointScore) {
          // convert normalized coords to pixel coords in captured image
          final double lx = (l['x'] ?? 0.0) * w;
          final double ly = (l['y'] ?? 0.0) * h;
          final double rx = (r['x'] ?? 0.0) * w;
          final double ry = (r['y'] ?? 0.0) * h;
          if (kDebugMode)
            debugPrint(
                'Shoulders raw: L=(${l['x']},${l['y']},${l['score']}) -> px=($lx,$ly), R=(${r['x']},${r['y']},${r['score']}) -> px=($rx,$ry)');
          setState(() {
            _leftShoulderMarker = Offset(lx, ly);
            _rightShoulderMarker = Offset(rx, ry);
            _shoulderMissCount = 0;
          });
          return;
        }
      }

      // fallback to heuristics per-frame (cheap)
      try {
        final improved = _detectLinesImprovedFromRgba(rgba, w, h);
        final int leftShoulderX = (improved['leftShoulderX'] as int?) ?? -1;
        final int rightShoulderX = (improved['rightShoulderX'] as int?) ?? -1;
        final int shoulderRow = (improved['shoulderRow'] as int?) ?? -1;
        if (leftShoulderX >= 0 && rightShoulderX >= 0 && shoulderRow >= 0) {
          setState(() {
            // store as pixel coordinates relative to captured image for consistent mapping
            _leftShoulderMarker =
                Offset(leftShoulderX.toDouble(), shoulderRow.toDouble());
            _rightShoulderMarker =
                Offset(rightShoulderX.toDouble(), shoulderRow.toDouble());
            _shoulderMissCount = 0;
          });
          return;
        }
      } catch (_) {}

      // no reliable detection this frame
      _shoulderMissCount++;
      if (_shoulderMissCount >= _maxShoulderMiss) {
        setState(() {
          _leftShoulderMarker = null;
          _rightShoulderMarker = null;
        });
      }
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<void> _captureAndAnalyzeFrame() async {
    setState(() {
      _analysisRunning = true;
      _detectedLines = [];
    });
    try {
      final renderObj = _videoRepaintKey.currentContext?.findRenderObject();
      if (renderObj is! RenderRepaintBoundary) return;
      final boundary = renderObj;
      final ui.Image captured = await boundary.toImage(pixelRatio: 1.0);
      final byteData =
          await captured.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return;
      final rgba = byteData.buffer.asUint8List();
      final w = captured.width;
      final h = captured.height;
      // remember captured image size for accurate mapping to canvas
      _lastCapturedImageSize = Size(w.toDouble(), h.toDouble());
      List<DetectedLine> detected = [];

      // If MoveNet loaded successfully and user enabled it, run it on the captured RGBA frame.
      List<Map<String, double>>? kpRes;
      List<List<double>>? rawOutForDebug;
      Map<String, int>? cropMetaForDebug;
      if (_useMoveNet && MoveNetManager.interpreter != null) {
        try {
          final movenetResult = await _runMoveNetWithRaw(rgba, w, h);
          if (movenetResult != null) {
            kpRes = movenetResult['keypoints'] as List<Map<String, double>>?;
            rawOutForDebug = movenetResult['raw'] as List<List<double>>?;
            cropMetaForDebug = movenetResult['crop'] as Map<String, int>?;
          }
          if (kpRes != null && kpRes.isNotEmpty) {
            // MoveNet outputs keypoints as list of {y,x,score}
            // Indices: 5=leftShoulder,6=rightShoulder,11=leftHip,12=rightHip,7/8 elbows,9/10 wrists
            final leftShoulder = kpRes[5];
            final rightShoulder = kpRes[6];
            final leftHip = kpRes[11];
            final rightHip = kpRes[12];
            final leftElbow = kpRes[7];
            final rightElbow = kpRes[8];
            final leftWrist = kpRes[9];
            final rightWrist = kpRes[10];

            final lsx = (leftShoulder['x']! * w).clamp(0, w).toDouble();
            final rshx = (rightShoulder['x']! * w).clamp(0, w).toDouble();
            final sRow = ((leftShoulder['y']! + rightShoulder['y']!) * 0.5 * h)
                .clamp(0, h)
                .toDouble();

            detected.add(DetectedLine(
                p1: Offset(lsx / w, sRow / h),
                p2: Offset(rshx / w, sRow / h),
                label: 'Shoulder',
                color: Colors.yellow));

            final spineX = ((leftShoulder['x']! +
                        rightShoulder['x']! +
                        leftHip['x']! +
                        rightHip['x']!) /
                    4.0) *
                w;
            detected.add(DetectedLine(
                p1: Offset(spineX / w, 0.05),
                p2: Offset(spineX / w, 0.95),
                label: 'Spine',
                color: Colors.cyan));

            // Shaft: prefer the wrist/elbow pair with higher wrist score
            Map<String, double> chosenWrist =
                rightWrist['score']! >= leftWrist['score']!
                    ? rightWrist
                    : leftWrist;
            Map<String, double> chosenElbow =
                rightElbow['score']! >= leftElbow['score']!
                    ? rightElbow
                    : leftElbow;
            // convert to image coords
            final p1 = Offset((chosenElbow['x']! * w), (chosenElbow['y']! * h));
            final p2 = Offset((chosenWrist['x']! * w), (chosenWrist['y']! * h));
            // only add shaft if wrist/elbow scores exceed threshold
            if ((chosenWrist['score'] ?? 0.0) >= _minKeypointScore &&
                (chosenElbow['score'] ?? 0.0) >= _minKeypointScore) {
              detected.add(DetectedLine(
                  p1: Offset(p1.dx / w, p1.dy / h),
                  p2: Offset(p2.dx / w, p2.dy / h),
                  label: 'Shaft',
                  color: Colors.greenAccent));
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('MoveNet inference failed: $e');
        }
      }

      // If MoveNet did not produce results, fall back to the improved heuristic detector
      if (detected.isEmpty) {
        final improved = _detectLinesImprovedFromRgba(rgba, w, h);
        final int shoulderRow = (improved['shoulderRow'] as int?) ?? -1;
        final int spineCol = (improved['spineCol'] as int?) ?? -1;
        final int leftShoulderX = (improved['leftShoulderX'] as int?) ?? -1;
        final int rightShoulderX = (improved['rightShoulderX'] as int?) ?? -1;
        final List<Offset>? shaft = improved['shaftPoints'] as List<Offset>?;

        if (leftShoulderX >= 0 && rightShoulderX >= 0) {
          detected.add(DetectedLine(
              p1: Offset(leftShoulderX / w, shoulderRow / h),
              p2: Offset(rightShoulderX / w, shoulderRow / h),
              label: 'Shoulder',
              color: Colors.yellow));
        }
        if (spineCol >= 0) {
          detected.add(DetectedLine(
              p1: Offset(spineCol / w, 0.05),
              p2: Offset(spineCol / w, 0.95),
              label: 'Spine',
              color: Colors.cyan));
        }
        if (shaft != null && shaft.length >= 2) {
          detected.add(DetectedLine(
              p1: Offset(shaft[0].dx / w, shaft[0].dy / h),
              p2: Offset(shaft[1].dx / w, shaft[1].dy / h),
              label: 'Shaft',
              color: Colors.greenAccent));
        }
      }
      final lines = detected;
      // store last keypoints if available for export
      if (kpRes != null && kpRes.isNotEmpty) {
        _lastKeypoints = kpRes;
      } else {
        _lastKeypoints = null;
      }

      if (mounted) {
        setState(() {
          _detectedLines = lines;
        });
      }
      // Append batch record for data collection
      try {
        final Map<String, Object?> doc = {
          'timestamp': DateTime.now().toIso8601String(),
          'keypoints': _lastKeypoints,
          'detected_lines': _detectedLines
              .map((l) => {
                    'label': l.label,
                    'p1': {'x': l.p1.dx, 'y': l.p1.dy},
                    'p2': {'x': l.p2.dx, 'y': l.p2.dy},
                  })
              .toList(),
        };
        _appendBatchRecord(doc);
        try {
          final dir = await getApplicationDocumentsDirectory();
          final outDir = Directory(
              '${dir.path}${Platform.pathSeparator}smart_range_coach');
          if (!await outDir.exists()) await outDir.create(recursive: true);
          final ts = DateTime.now();
          final outPath =
              '${outDir.path}${Platform.pathSeparator}debug_${ts.toIso8601String().replaceAll(':', '-')}.json';
          final Map<String, Object?> dump = {
            'timestamp': ts.toIso8601String(),
            'captured_w': w,
            'captured_h': h,
            'use_movenet': _useMoveNet,
            'movenet_loaded': MoveNetManager.interpreter != null,
            'crop': cropMetaForDebug ?? _lastCrop,
            'movenet_raw_output': rawOutForDebug,
            'remapped_keypoints': kpRes,
            'detected_lines': _detectedLines
                .map((l) => {
                      'label': l.label,
                      'p1': {'x': l.p1.dx, 'y': l.p1.dy},
                      'p2': {'x': l.p2.dx, 'y': l.p2.dy},
                    })
                .toList(),
          };
          final f = File(outPath);
          await f
              .writeAsString(const JsonEncoder.withIndent('  ').convert(dump));
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Debug dumped to $outPath')));
        } catch (e) {
          if (kDebugMode) debugPrint('per-frame debug write failed: $e');
        }
      } catch (_) {}
    } catch (e) {
      if (kDebugMode) debugPrint('Frame analysis failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _analysisRunning = false;
        });
      }
    }
  }

  // Run a lightweight MoveNet inference on the raw RGBA frame.
  // Returns a list of 17 keypoints where each keypoint is a map { 'y': double, 'x': double, 'score': double }

  // FPS-Counter für Debug-Logging
  static int _movenetCallCount = 0;
  static DateTime? _movenetLastLog;

  Future<List<Map<String, double>>?> _runMoveNetOnRgba(
      Uint8List rgba, int w, int h) async {
    if (MoveNetManager.interpreter == null) return null;

    // FPS-Logging
    _movenetCallCount++;
    if (_movenetLastLog == null ||
        DateTime.now().difference(_movenetLastLog!) >
            const Duration(seconds: 1)) {
      if (kDebugMode) debugPrint('✅ MoveNet FPS: $_movenetCallCount calls/sec');
      _movenetCallCount = 0;
      _movenetLastLog = DateTime.now();
    }
    try {
      final int size = _movenetInputSize;
      // Build input using bilinear resize in an Isolate (center-crop -> resize)
      final Map<String, dynamic> prep = await compute(_resizeNormalize, {
        'rgba': rgba,
        'w': w,
        'h': h,
        'size': size,
        'centerCrop': _centerCropEnabled
      });
      final inputImage = prep['image'] as List<List<List<double>>>;
      final crop = prep['crop'] as Map<String, dynamic>;
      final int cropX = crop['x'] as int;
      final int cropY = crop['y'] as int;
      final int cropW = crop['w'] as int;
      final int cropH = crop['h'] as int;
      // store last crop for debug overlay mapping
      _lastCrop = {'x': cropX, 'y': cropY, 'w': cropW, 'h': cropH};
      // Konvertiere zu Uint8List (256x256x3 = 196608 bytes)
      final Uint8List uint8Input = Uint8List(size * size * 3);
      int idx = 0;
      for (int ty = 0; ty < size; ty++) {
        for (int tx = 0; tx < size; tx++) {
          for (int c = 0; c < 3; c++) {
            uint8Input[idx++] =
                (inputImage[ty][tx][c] * 255).round().clamp(0, 255);
          }
        }
      }

      // Reshape zu [1, size, size, 3] für TFLite
      final input = uint8Input.buffer.asUint8List().reshape([1, size, size, 3]);
      final output = List.generate(
          1,
          (_) => List.generate(
              1, (_) => List.generate(17, (_) => List.filled(3, 0.0))));

      MoveNetManager.interpreter!.run(input, output);

      final List<Map<String, double>> kps = [];
      final out0 = output[0][0];
      for (int i = 0; i < 17; i++) {
        final y = out0[i][0];
        final x = out0[i][1];
        final score = out0[i][2];
        // remap from model-input (cropped square) normalized coords back to original image normalized coords
        final double origX = (cropX + x * cropW) / w;
        final double origY = (cropY + y * cropH) / h;
        kps.add({'y': origY, 'x': origX, 'score': score});
      }
      return kps;
    } catch (e) {
      if (kDebugMode) debugPrint('MoveNet run error: $e');
      return null;
    }
  }

  // Variant of MoveNet runner that also returns the raw output (for debugging)
  Future<Map<String, Object?>?> _runMoveNetWithRaw(
      Uint8List rgba, int w, int h) async {
    if (MoveNetManager.interpreter == null) return null;
    try {
      final int size = _movenetInputSize;
      final Map<String, dynamic> prep = await compute(_resizeNormalize, {
        'rgba': rgba,
        'w': w,
        'h': h,
        'size': size,
        'centerCrop': _centerCropEnabled
      });
      final inputImage = prep['image'] as List<List<List<double>>>;
      final crop = prep['crop'] as Map<String, dynamic>;
      final int cropX = crop['x'] as int;
      final int cropY = crop['y'] as int;
      final int cropW = crop['w'] as int;
      final int cropH = crop['h'] as int;
      // store last crop for debug overlay mapping
      _lastCrop = {'x': cropX, 'y': cropY, 'w': cropW, 'h': cropH};

      // Konvertiere zu Uint8List
      final Uint8List uint8Input = Uint8List(size * size * 3);
      int idx = 0;
      for (int ty = 0; ty < size; ty++) {
        for (int tx = 0; tx < size; tx++) {
          for (int c = 0; c < 3; c++) {
            uint8Input[idx++] =
                (inputImage[ty][tx][c] * 255).round().clamp(0, 255);
          }
        }
      }

      final input = uint8Input.buffer.asUint8List().reshape([1, size, size, 3]);
      final output = List.generate(
          1,
          (_) => List.generate(
              1, (_) => List.generate(17, (_) => List.filled(3, 0.0))));
      MoveNetManager.interpreter!.run(input, output);

      final List<Map<String, double>> kps = [];
      final List<List<double>> raw = [];
      final out0 = output[0][0];
      for (int i = 0; i < 17; i++) {
        final y = out0[i][0];
        final x = out0[i][1];
        final score = out0[i][2];
        raw.add([y, x, score]);
        final double origX = (cropX + x * cropW) / w;
        final double origY = (cropY + y * cropH) / h;
        kps.add({'y': origY, 'x': origX, 'score': score});
      }

      return {
        'keypoints': kps,
        'raw': raw,
        'crop': {'x': cropX, 'y': cropY, 'w': cropW, 'h': cropH}
      };
    } catch (e) {
      if (kDebugMode) debugPrint('MoveNet run error (with raw): $e');
      return null;
    }
  }

  Future<void> _exportLastResults() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final outDir =
          Directory('${dir.path}${Platform.pathSeparator}smart_range_coach');
      if (!await outDir.exists()) await outDir.create(recursive: true);
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final outPath =
          '${outDir.path}${Platform.pathSeparator}pose_$timestamp.json';

      final Map<String, Object?> doc = {};
      doc['timestamp'] = DateTime.now().toIso8601String();
      if (_lastKeypoints != null) {
        doc['keypoints'] = _lastKeypoints;
      }
      // also include detected lines (normalized)
      doc['detected_lines'] = _detectedLines
          .map((l) => {
                'label': l.label,
                'p1': {'x': l.p1.dx, 'y': l.p1.dy},
                'p2': {'x': l.p2.dx, 'y': l.p2.dy},
              })
          .toList();

      final f = File(outPath);
      await f.writeAsString(jsonEncode(doc));
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Exported $outPath')));
    } catch (e) {
      if (kDebugMode) debugPrint('Export failed: $e');
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Export failed')));
    }
  }

  // Dump debug JSON containing captured frame metadata, crop, raw MoveNet output (if any),
  // remapped keypoints, and detected lines. Useful for offline inspection.
  Future<void> _dumpDebugJson() async {
    setState(() {
      _analysisRunning = true;
    });
    try {
      final renderObj = _videoRepaintKey.currentContext?.findRenderObject();
      if (renderObj is! RenderRepaintBoundary) return;
      final boundary = renderObj;
      final ui.Image captured = await boundary.toImage(pixelRatio: 1.0);
      final byteData =
          await captured.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return;
      final rgba = byteData.buffer.asUint8List();
      final w = captured.width;
      final h = captured.height;

      final Map<String, Object?> outDoc = {};
      outDoc['timestamp'] = DateTime.now().toIso8601String();
      outDoc['captured_w'] = w;
      outDoc['captured_h'] = h;
      outDoc['use_movenet'] = _useMoveNet;
      outDoc['movenet_loaded'] = MoveNetManager.interpreter != null;

      List<Map<String, double>>? remappedKps;
      List<List<List<double>>>? inputImage;
      Map<String, int>? cropMeta;
      List<List<double>>? rawOut; // flattened raw output rows
      String? movenetError;

      try {
        final int size = _movenetInputSize;
        final Map<String, dynamic> prep = await compute(_resizeNormalize, {
          'rgba': rgba,
          'w': w,
          'h': h,
          'size': size,
          'centerCrop': _centerCropEnabled
        });
        inputImage = prep['image'] as List<List<List<double>>>;
        final crop = prep['crop'] as Map<String, dynamic>;
        cropMeta = {
          'x': crop['x'] as int,
          'y': crop['y'] as int,
          'w': crop['w'] as int,
          'h': crop['h'] as int
        };

        if (_useMoveNet && MoveNetManager.interpreter != null) {
          // Build model input and run interpreter capturing raw outputs
          // Konvertiere zu Uint8List
          final Uint8List uint8Input = Uint8List(size * size * 3);
          int idx = 0;
          for (int ty = 0; ty < size; ty++) {
            for (int tx = 0; tx < size; tx++) {
              for (int c = 0; c < 3; c++) {
                uint8Input[idx++] =
                    (inputImage[ty][tx][c] * 255).round().clamp(0, 255);
              }
            }
          }

          final input =
              uint8Input.buffer.asUint8List().reshape([1, size, size, 3]);
          final output = List.generate(
              1,
              (_) => List.generate(
                  1, (_) => List.generate(17, (_) => List.filled(3, 0.0))));
          try {
            MoveNetManager.interpreter!.run(input, output);
            rawOut = [];
            final out0 = output[0][0];
            for (int i = 0; i < 17; i++) {
              rawOut.add([out0[i][0], out0[i][1], out0[i][2]]);
            }
            // remap
            remappedKps = [];
            for (int i = 0; i < 17; i++) {
              final y = out0[i][0];
              final x = out0[i][1];
              final score = out0[i][2];
              final double origX = (cropMeta['x']! + x * cropMeta['w']!) / w;
              final double origY = (cropMeta['y']! + y * cropMeta['h']!) / h;
              remappedKps.add({'y': origY, 'x': origX, 'score': score});
            }
          } catch (e) {
            movenetError = e.toString();
          }
        }
      } catch (e) {
        movenetError = e.toString();
      }

      // Also include detected lines (use MoveNet results if available, else heuristic)
      final List<Map<String, Object?>> detectedLinesForDump = [];
      if (remappedKps != null && remappedKps.isNotEmpty) {
        try {
          final leftShoulder = remappedKps[5];
          final rightShoulder = remappedKps[6];
          final leftHip = remappedKps[11];
          final rightHip = remappedKps[12];
          final leftElbow = remappedKps[7];
          final rightElbow = remappedKps[8];
          final leftWrist = remappedKps[9];
          final rightWrist = remappedKps[10];

          final lsx = (leftShoulder['x']! * w).clamp(0, w).toDouble();
          final rshx = (rightShoulder['x']! * w).clamp(0, w).toDouble();
          final sRow = ((leftShoulder['y']! + rightShoulder['y']!) * 0.5 * h)
              .clamp(0, h)
              .toDouble();
          detectedLinesForDump.add({
            'label': 'Shoulder',
            'p1': {'x': lsx / w, 'y': sRow / h},
            'p2': {'x': rshx / w, 'y': sRow / h}
          });

          final spineX = ((leftShoulder['x']! +
                      rightShoulder['x']! +
                      leftHip['x']! +
                      rightHip['x']!) /
                  4.0) *
              w;
          detectedLinesForDump.add({
            'label': 'Spine',
            'p1': {'x': spineX / w, 'y': 0.05},
            'p2': {'x': spineX / w, 'y': 0.95}
          });

          Map<String, double> chosenWrist =
              rightWrist['score']! >= leftWrist['score']!
                  ? rightWrist
                  : leftWrist;
          Map<String, double> chosenElbow =
              rightElbow['score']! >= leftElbow['score']!
                  ? rightElbow
                  : leftElbow;
          if ((chosenWrist['score'] ?? 0.0) >= _minKeypointScore &&
              (chosenElbow['score'] ?? 0.0) >= _minKeypointScore) {
            final p1 = Offset((chosenElbow['x']! * w), (chosenElbow['y']! * h));
            final p2 = Offset((chosenWrist['x']! * w), (chosenWrist['y']! * h));
            detectedLinesForDump.add({
              'label': 'Shaft',
              'p1': {'x': p1.dx / w, 'y': p1.dy / h},
              'p2': {'x': p2.dx / w, 'y': p2.dy / h}
            });
          }
        } catch (_) {}
      } else {
        try {
          final improved = _detectLinesImprovedFromRgba(rgba, w, h);
          detectedLinesForDump.add({
            'label': 'Shoulder',
            'p1': {
              'x': ((improved['leftShoulderX'] as int? ?? -1) / w),
              'y': ((improved['shoulderRow'] as int? ?? -1) / h)
            },
            'p2': {
              'x': ((improved['rightShoulderX'] as int? ?? -1) / w),
              'y': ((improved['shoulderRow'] as int? ?? -1) / h)
            }
          });
          detectedLinesForDump.add({
            'label': 'Spine',
            'p1': {'x': ((improved['spineCol'] as int? ?? -1) / w), 'y': 0.05},
            'p2': {'x': ((improved['spineCol'] as int? ?? -1) / w), 'y': 0.95}
          });
          final List<Offset>? shaft = improved['shaftPoints'] as List<Offset>?;
          if (shaft != null && shaft.length >= 2) {
            detectedLinesForDump.add({
              'label': 'Shaft',
              'p1': {'x': shaft[0].dx / w, 'y': shaft[0].dy / h},
              'p2': {'x': shaft[1].dx / w, 'y': shaft[1].dy / h}
            });
          }
        } catch (_) {}
      }

      outDoc['crop'] = cropMeta;
      outDoc['movenet_raw_output'] = rawOut;
      outDoc['movenet_error'] = movenetError;
      outDoc['remapped_keypoints'] = remappedKps;
      outDoc['detected_lines'] = detectedLinesForDump;

      final dir = await getApplicationDocumentsDirectory();
      final outDir =
          Directory('${dir.path}${Platform.pathSeparator}smart_range_coach');
      if (!await outDir.exists()) await outDir.create(recursive: true);
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final outPath =
          '${outDir.path}${Platform.pathSeparator}debug_$timestamp.json';
      final f = File(outPath);
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert(outDoc));
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Debug dumped to $outPath')));
    } catch (e) {
      if (kDebugMode) debugPrint('Dump debug failed: $e');
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Dump debug failed')));
    } finally {
      if (mounted)
        setState(() {
          _analysisRunning = false;
        });
    }
  }

  // Append a single NDJSON record for batch collection (non-blocking)
  Future<void> _appendBatchRecord(Map<String, Object?> doc) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final outDir =
          Directory('${dir.path}${Platform.pathSeparator}smart_range_coach');
      if (!await outDir.exists()) await outDir.create(recursive: true);
      final file =
          File('${outDir.path}${Platform.pathSeparator}analysis_batch.ndjson');
      final sink = file.openWrite(mode: FileMode.append);
      sink.writeln(jsonEncode(doc));
      await sink.flush();
      await sink.close();
    } catch (e) {
      if (kDebugMode) debugPrint('Batch append failed: $e');
    }
  }

  // helper methods for raw rgba frames
  int _luminanceFromRgba(Uint8List rgba, int w, int x, int y) {
    final idx = (y * w + x) * 4;
    final r = rgba[idx];
    final g = rgba[idx + 1];
    final b = rgba[idx + 2];
    return ((0.299 * r) + (0.587 * g) + (0.114 * b)).round();
  }

  // Improved detector: downsample, build a luminance mask, find largest connected
  // component (assumed human), then infer shoulders/spine/shaft more robustly.
  Map<String, Object?> _detectLinesImprovedFromRgba(
      Uint8List rgba, int w, int h) {
    // target a manageable width to keep analysis fast
    final int targetW = 320;
    int scale = (w / targetW).ceil();
    if (scale < 1) scale = 1;
    if (scale > w) scale = w;
    final int sw = (w / scale).ceil();
    final int sh = (h / scale).ceil();

    // build sampled luminance buffer
    final List<int> L = List<int>.filled(sw * sh, 0);
    for (int yy = 0; yy < sh; yy++) {
      final int oy = (yy * scale).clamp(0, h - 1);
      for (int xx = 0; xx < sw; xx++) {
        final int ox = (xx * scale).clamp(0, w - 1);
        L[yy * sw + xx] = _luminanceFromRgba(rgba, w, ox, oy);
      }
    }

    // compute mean and stddev
    double sum = 0;
    for (final v in L) sum += v;
    final double mean = sum / L.length;
    double varSum = 0;
    for (final v in L) varSum += (v - mean) * (v - mean);
    final double std = (varSum / L.length);
    // use dart:math sqrt
    final double stdDev = std > 0 ? (math.sqrt(std)) : 0.0;

    final int thresh = (stdDev * 0.6).round().clamp(8, 48);

    // binary mask where luminance differs from mean by thresh
    final List<int> mask = List<int>.filled(sw * sh, 0);
    for (int i = 0; i < L.length; i++) {
      mask[i] = ((L[i] - mean).abs() > thresh) ? 1 : 0;
    }

    // flood-fill largest connected component
    final visited = List<int>.filled(sw * sh, 0);
    int bestCount = 0;
    int bestLabel = -1;
    final List<int> labels = List<int>.filled(sw * sh, 0);
    int label = 0;
    final q = <int>[];
    for (int y = 0; y < sh; y++) {
      for (int x = 0; x < sw; x++) {
        final idx = y * sw + x;
        if (mask[idx] == 0 || visited[idx] == 1) continue;
        // new component
        label++;
        int cnt = 0;
        q.clear();
        q.add(idx);
        visited[idx] = 1;
        labels[idx] = label;
        while (q.isNotEmpty) {
          final cur = q.removeLast();
          cnt++;
          final cy = cur ~/ sw;
          final cx = cur % sw;
          for (int oyOff = -1; oyOff <= 1; oyOff++) {
            for (int oxOff = -1; oxOff <= 1; oxOff++) {
              final nx = cx + oxOff;
              final ny = cy + oyOff;
              if (nx < 0 || nx >= sw || ny < 0 || ny >= sh) continue;
              final nidx = ny * sw + nx;
              if (visited[nidx] == 1) continue;
              if (mask[nidx] == 0) continue;
              visited[nidx] = 1;
              labels[nidx] = label;
              q.add(nidx);
            }
          }
        }
        if (cnt > bestCount) {
          bestCount = cnt;
          bestLabel = label;
        }
      }
    }

    if (bestCount < 40) {
      return <String, Object?>{}; // nothing reliable
    }

    // compute bounding box of bestLabel
    int minx = sw, miny = sh, maxx = 0, maxy = 0;
    for (int y = 0; y < sh; y++) {
      for (int x = 0; x < sw; x++) {
        final idx = y * sw + x;
        if (labels[idx] == bestLabel) {
          if (x < minx) minx = x;
          if (x > maxx) maxx = x;
          if (y < miny) miny = y;
          if (y > maxy) maxy = y;
        }
      }
    }

    // find shoulder row: in upper bbox area find row with widest span
    int bestRow = miny;
    int bestWidth = 0;
    final int searchTop = miny;
    final int searchBottom = miny + ((maxy - miny) / 2).floor();
    for (int y = searchTop; y <= searchBottom; y++) {
      int left = -1, right = -1;
      for (int x = minx; x <= maxx; x++) {
        if (labels[y * sw + x] == bestLabel) {
          if (left == -1) left = x;
          right = x;
        }
      }
      if (left != -1) {
        final wspan = right - left;
        if (wspan > bestWidth) {
          bestWidth = wspan;
          bestRow = y;
        }
      }
    }

    int leftShoulder = -1, rightShoulder = -1;
    for (int x = minx; x <= maxx; x++) {
      if (labels[bestRow * sw + x] == bestLabel) {
        if (leftShoulder == -1) leftShoulder = x;
        rightShoulder = x;
      }
    }

    // spine: choose column with most labelled pixels within bbox
    int bestCol = minx;
    int bestColCount = -1;
    for (int x = minx; x <= maxx; x++) {
      int c = 0;
      for (int y = miny; y <= maxy; y++) {
        if (labels[y * sw + x] == bestLabel) c++;
      }
      if (c > bestColCount) {
        bestColCount = c;
        bestCol = x;
      }
    }

    // shaft: collect strong-edge points in lower bbox and fit a line
    final List<Offset> pts = [];
    final int yStart = miny + ((maxy - miny) * 0.4).floor();
    final int yEnd = maxy;
    for (int y = yStart; y <= yEnd; y++) {
      for (int x = minx; x <= maxx; x++) {
        if (labels[y * sw + x] != bestLabel) continue;
        // compute simple gradient
        final int lx = (x - 1).clamp(0, sw - 1);
        final int rx = (x + 1).clamp(0, sw - 1);
        final int uy = (y - 1).clamp(0, sh - 1);
        final int dy = (y + 1).clamp(0, sh - 1);
        final int gx = (L[y * sw + rx] - L[y * sw + lx]).abs();
        final int gy = (L[dy * sw + x] - L[uy * sw + x]).abs();
        final int g = gx + gy;
        if (g > 40) {
          pts.add(Offset((x * scale).toDouble(), (y * scale).toDouble()));
        }
      }
    }

    List<Offset>? shaftLine;
    if (pts.length >= 6) {
      double sumX = 0, sumY = 0, sumXY = 0, sumXX = 0;
      for (final p in pts) {
        sumX += p.dx;
        sumY += p.dy;
        sumXY += p.dx * p.dy;
        sumXX += p.dx * p.dx;
      }
      final n = pts.length.toDouble();
      final denom = (n * sumXX - sumX * sumX);
      if (denom.abs() >= 1e-6) {
        final a = (n * sumXY - sumX * sumY) / denom;
        final b = (sumY - a * sumX) / n;
        final x1 = (minx * scale + 0.0);
        final x2 = (maxx * scale + 0.0);
        final y1 = a * x1 + b;
        final y2 = a * x2 + b;
        shaftLine = [Offset(x1, y1), Offset(x2, y2)];
      }
    }

    return {
      'shoulderRow': bestRow * scale,
      'spineCol': bestCol * scale,
      'leftShoulderX': (leftShoulder >= 0) ? leftShoulder * scale : -1,
      'rightShoulderX': (rightShoulder >= 0) ? rightShoulder * scale : -1,
      'shaftPoints': shaftLine,
    };
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;

    return Scaffold(
      appBar: AppBar(title: Text('Swing ${widget.swingNumber}: Review')),
      // Persistent Analyse FAB so it's always visible to the user
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Builder(builder: (ctx) {
        final ctrl = _controller;
        return FloatingActionButton.extended(
          heroTag: 'analyse_frame_scaffold',
          backgroundColor: Colors.blueAccent,
          icon: const Icon(Icons.search),
          label: _analysisRunning
              ? const Text('Analysiere...')
              : const Text('Analyse'),
          onPressed:
              (_analysisRunning || ctrl == null || !ctrl.value.isInitialized)
                  ? null
                  : () async {
                      try {
                        await ctrl.pause();
                        if (mounted) {
                          setState(() {});
                        }
                        await _captureAndAnalyzeFrame();
                      } catch (e) {
                        if (kDebugMode)
                          debugPrint('Scaffold Analyse FAB error: $e');
                      }
                    },
        );
      }),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_videoError != null)
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Card(
                      color: Colors.orange.withAlpha((0.12 * 255).round()),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.orangeAccent),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(_videoError!,
                                    style: const TextStyle(
                                        color: Colors.orangeAccent))),
                            TextButton(
                                onPressed: _initVideo,
                                child: const Text('Erneut versuchen')),
                          ],
                        ),
                      ),
                    ),
                  ),

                if (_videoReady && ctrl != null)
                  AspectRatio(
                    aspectRatio: ctrl.value.aspectRatio == 0
                        ? 16 / 9
                        : ctrl.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        RepaintBoundary(
                          key: _videoRepaintKey,
                          child: VideoPlayer(ctrl),
                        ),
                        // Keypoints overlay (if available)
                        if (_lastKeypoints != null)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: KeypointsPainter(
                                  keypoints: _lastKeypoints!,
                                  minScore: _minKeypointScore,
                                  imageSize: _lastCapturedImageSize ??
                                      Size(ctrl.value.size.width,
                                          ctrl.value.size.height)),
                            ),
                          ),
                        // Persistent body markers
                        if (_allKeypoints != null && _allKeypoints!.isNotEmpty)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _PoseKeyPointsPainter(
                                  keypoints: _allKeypoints,
                                  imageSize: _lastCapturedImageSize ??
                                      Size(ctrl.value.size.width,
                                          ctrl.value.size.height)),
                            ),
                          ),
                        // Crop debug overlay
                        if (_lastCrop != null)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _CropPainter(
                                  crop: _lastCrop!,
                                  imageSize: Size(ctrl.value.size.width,
                                      ctrl.value.size.height)),
                            ),
                          ),
                        // Large centered play button overlay when paused/still
                        if (!(ctrl.value.isPlaying))
                          Positioned.fill(
                            child: Container(
                              color: Colors.black26,
                              child: Center(
                                child: SizedBox(
                                  width: 96,
                                  height: 96,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      shape: const CircleBorder(),
                                      backgroundColor: Colors.white70,
                                      foregroundColor: Colors.black87,
                                      elevation: 6,
                                    ),
                                    onPressed: () async {
                                      try {
                                        // If at end, rewind a bit or to start
                                        final dur = ctrl.value.duration;
                                        final pos = ctrl.value.position;
                                        if (dur != Duration.zero &&
                                            pos >=
                                                dur -
                                                    const Duration(
                                                        milliseconds: 150)) {
                                          await ctrl.seekTo(Duration.zero);
                                        }
                                        await ctrl.play();
                                      } catch (e) {
                                        if (kDebugMode)
                                          debugPrint('Play overlay error: $e');
                                      }
                                      if (mounted) {
                                        setState(() {});
                                      }
                                    },
                                    child:
                                        const Icon(Icons.play_arrow, size: 48),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        // if we have detected lines, draw them as an overlay
                        if (_detectedLines.isNotEmpty)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: LinesPainter(lines: _detectedLines),
                            ),
                          ),
                        // Prominent floating Analyse button at bottom-right of the video
                        Positioned(
                          bottom: 12,
                          right: 12,
                          child: FloatingActionButton.extended(
                            heroTag: 'analyse_frame',
                            backgroundColor: Colors.blueAccent,
                            icon: const Icon(Icons.search),
                            label: _analysisRunning
                                ? const Text('Analysiere...')
                                : const Text('Analyse'),
                            onPressed:
                                _analysisRunning || !ctrl.value.isInitialized
                                    ? null
                                    : () async {
                                        try {
                                          await ctrl.pause();
                                          if (mounted) {
                                            setState(() {});
                                          }
                                          await _captureAndAnalyzeFrame();
                                        } catch (e) {
                                          if (kDebugMode)
                                            debugPrint('Analyse FAB error: $e');
                                        }
                                      },
                          ),
                        ),
                        // Vergleich mit Profi Button
                        Positioned(
                          bottom: 80,
                          right: 12,
                          child: FloatingActionButton.extended(
                            heroTag: 'compare_pro',
                            backgroundColor: Colors.purple,
                            icon: const Icon(Icons.compare_arrows),
                            label: const Text('Vergleich'),
                            onPressed: () async {
                              // Prüfe ob Pose-Daten existieren
                              final poseJsonPath = widget.videoPath
                                  .replaceAll('.mp4', '_pose_data.json');
                              final file = File(poseJsonPath);

                              if (await file.exists()) {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => SwingComparisonScreen(
                                      userVideoPath: widget.videoPath,
                                    ),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                        'Bitte zuerst Video mit MediaPipe analysieren'),
                                    action: SnackBarAction(
                                      label: 'Analysieren',
                                      onPressed: () async {
                                        await _analyzeVideoAndSaveShoulders(
                                            widget.videoPath);
                                      },
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                // Minimal controls
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon((ctrl?.value.isPlaying ?? false)
                            ? Icons.pause
                            : Icons.play_arrow),
                        onPressed: ctrl == null
                            ? null
                            : () async {
                                try {
                                  if (ctrl.value.isPlaying) {
                                    await ctrl.pause();
                                  } else {
                                    // If we're at (or very near) the end, rewind to start first
                                    final dur = ctrl.value.duration;
                                    final pos = ctrl.value.position;
                                    if (dur != Duration.zero &&
                                        pos >=
                                            dur -
                                                const Duration(
                                                    milliseconds: 150)) {
                                      await ctrl.seekTo(Duration.zero);
                                    }
                                    await ctrl.play();
                                  }
                                } catch (e) {
                                  // ignore play errors but surface via setState so UI updates
                                }
                                if (mounted) {
                                  setState(() {});
                                }
                              },
                      ),
                      const SizedBox(width: 8),
                      // Capture frame & analyze
                      ElevatedButton.icon(
                        onPressed: _analysisRunning ||
                                ctrl == null ||
                                !ctrl.value.isInitialized
                            ? null
                            : () async {
                                // Pause first to capture a clean frame
                                await ctrl.pause();
                                if (mounted) setState(() {});
                                await _captureAndAnalyzeFrame();
                              },
                        icon: const Icon(Icons.search),
                        label: _analysisRunning
                            ? const Text('Analysiere...')
                            : const Text('Analyse Frame'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_previous),
                        onPressed: ctrl == null
                            ? null
                            : () async {
                                final p = ctrl.value.position;
                                final target =
                                    p - const Duration(milliseconds: 33);
                                await ctrl.seekTo(target >= Duration.zero
                                    ? target
                                    : Duration.zero);
                              },
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        onPressed: ctrl == null
                            ? null
                            : () async {
                                final p = ctrl.value.position;
                                final target =
                                    p + const Duration(milliseconds: 33);
                                await ctrl.seekTo(target <= ctrl.value.duration
                                    ? target
                                    : ctrl.value.duration);
                              },
                      ),
                    ],
                  ),
                ),

                // Checklist area mit MoveNet Controls und Buttons (alles scrollbar)
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Markiere, was du in diesem Swing erkennst',
                            style: TextStyle(color: Colors.white70)),
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              children: Issue.values.map((issue) {
                                return CheckboxListTile(
                                  value: _selected.contains(issue),
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selected.add(issue);
                                      } else {
                                        _selected.remove(issue);
                                      }
                                    });
                                  },
                                  title: Text(issueTitle(issue)),
                                  dense: true,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // MoveNet controls + export
                        Card(
                          color: Colors.blueGrey.shade900,
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('🎯 MoveNet Einstellungen',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Text('Center-crop for MoveNet'),
                                    const Spacer(),
                                    Switch(
                                        value: _centerCropEnabled,
                                        onChanged: (v) {
                                          setState(() {
                                            _centerCropEnabled = v;
                                          });
                                        }),
                                  ],
                                ),
                                Row(
                                  children: [
                                    const Text('Use MoveNet'),
                                    const Spacer(),
                                    Switch(
                                      value: _useMoveNet,
                                      onChanged: (v) {
                                        setState(() {
                                          _useMoveNet = v;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                const Divider(color: Colors.white24),
                                const Text('Keypoint Sichtbarkeit',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Text('Min Score:'),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Slider(
                                        value: _minKeypointScore,
                                        min: 0.0,
                                        max: 1.0,
                                        divisions: 20,
                                        label: _minKeypointScore
                                            .toStringAsFixed(2),
                                        onChanged: (v) {
                                          setState(() {
                                            _minKeypointScore = v;
                                          });
                                        },
                                      ),
                                    ),
                                    SizedBox(
                                      width: 40,
                                      child: Text(
                                        _minKeypointScore.toStringAsFixed(2),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16),
                                        textAlign: TextAlign.right,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: (_lastKeypoints == null &&
                                              _detectedLines.isEmpty)
                                          ? null
                                          : () async {
                                              await _exportLastResults();
                                            },
                                      icon:
                                          const Icon(Icons.download, size: 18),
                                      label: const Text('Export JSON'),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      onPressed: _analysisRunning
                                          ? null
                                          : () async {
                                              await _dumpDebugJson();
                                            },
                                      icon: const Icon(Icons.bug_report,
                                          size: 18),
                                      label: const Text('Debug'),
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              Colors.deepOrangeAccent),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Save / Discard Buttons (innerhalb ScrollView)
                        SafeArea(
                          top: false,
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.of(context)
                                      .pop<Set<Issue>>(<Issue>{}),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                  ),
                                  child: const Text('Verwerfen',
                                      style: TextStyle(fontSize: 16)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => Navigator.of(context)
                                      .pop<Set<Issue>>(_selected),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                  ),
                                  child: const Text('Speichern',
                                      style: TextStyle(fontSize: 16)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // MoveNet Video-Analyse Methode mit adaptivem Multi-Threading
  Future<void> _analyzeVideoAndSaveShoulders(String videoPath) async {
    try {
      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('🏌️ Golf-Schwung-Analyse',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 12),
                Text(_analysisStatus,
                    style: TextStyle(fontSize: 14, color: Colors.white70)),
                SizedBox(height: 8),
                Text(_analysisProgress,
                    style: TextStyle(fontSize: 12, color: Colors.blue)),
              ],
            ),
          ),
        ),
      );

      await MoveNetManager.init();
      if (MoveNetManager.interpreter == null) {
        throw Exception('MoveNet konnte nicht geladen werden');
      }

      final tempController = VideoPlayerController.file(File(videoPath));
      await tempController.initialize();
      await tempController.pause();

      final duration = tempController.value.duration;
      final videoWidth = tempController.value.size.width.toInt();
      final videoHeight = tempController.value.size.height.toInt();

      if (kDebugMode) {
        debugPrint(
            '🎬 Video: ${videoWidth}x${videoHeight}, ${duration.inMilliseconds}ms');
      }

      // Overlay für Frame-Capture
      final GlobalKey repaintKey = GlobalKey();
      OverlayEntry? overlayEntry = OverlayEntry(
        builder: (context) => Positioned(
          left: -10000,
          top: -10000,
          child: RepaintBoundary(
            key: repaintKey,
            child: SizedBox(
              width: videoWidth.toDouble(),
              height: videoHeight.toDouble(),
              child: VideoPlayer(tempController),
            ),
          ),
        ),
      );

      Overlay.of(context).insert(overlayEntry);
      await Future.delayed(Duration(milliseconds: 500));

      // ===================================================================
      // PHASE 1: MOTION DETECTION (Quick-Scan mit 10fps)
      // ===================================================================
      _updateAnalysisStatus('Phase 1: Bewegungs-Erkennung...');

      final motionProfile = await _detectMotionProfile(
        tempController,
        repaintKey,
        duration.inMilliseconds,
      );

      if (kDebugMode) {
        debugPrint(
            '📊 Motion Profile detected: ${motionProfile.length} segments');
        for (final segment in motionProfile) {
          debugPrint('  ${segment.startMs}-${segment.endMs}ms: '
              '${segment.phase} (motion=${(segment.motionLevel * 100).toInt()}%) '
              '→ ${segment.recommendedFps}fps');
        }
      }

      // ===================================================================
      // PHASE 2: ADAPTIVE MULTI-THREADED ANALYSIS
      // ===================================================================
      _updateAnalysisStatus('Phase 2: Intelligente Analyse...');

      // Teile Segmente auf Worker auf (optimiert für moderne CPUs)
      final workerCount = Platform.numberOfProcessors.clamp(2, 6);
      final segmentsPerWorker = (motionProfile.length / workerCount).ceil();

      List<Future<List<Map<String, dynamic>>>> workerFutures = [];

      for (int workerIndex = 0; workerIndex < workerCount; workerIndex++) {
        final startIdx = workerIndex * segmentsPerWorker;
        final endIdx = ((workerIndex + 1) * segmentsPerWorker)
            .clamp(0, motionProfile.length);

        if (startIdx >= motionProfile.length) break;

        final workerSegments = motionProfile.sublist(startIdx, endIdx);

        workerFutures.add(
          _analyzeSegmentsWorker(
            videoPath: videoPath,
            segments: workerSegments,
            videoWidth: videoWidth,
            videoHeight: videoHeight,
            workerIndex: workerIndex,
          ),
        );

        if (kDebugMode) {
          debugPrint(
              '🔧 Worker $workerIndex: Processing ${workerSegments.length} segments');
        }
      }

      // Warte auf alle Worker
      final workerResults = await Future.wait(workerFutures);

      // Merge & Sort Ergebnisse
      List<Map<String, dynamic>> poseData = [];
      for (final workerResult in workerResults) {
        poseData.addAll(workerResult);
      }
      poseData.sort((a, b) =>
          (a['timestamp_ms'] as int).compareTo(b['timestamp_ms'] as int));

      if (kDebugMode) {
        debugPrint('✅ Total frames analyzed: ${poseData.length}');
      }

      // Cleanup
      overlayEntry.remove();
      await tempController.dispose();

      // ===================================================================
      // PHASE 3: SAVE RESULTS
      // ===================================================================
      _updateAnalysisStatus('Phase 3: Speichere Ergebnisse...');

      if (poseData.isNotEmpty) {
        // Vollständige Pose-Daten mit Metadata
        final jsonPath = videoPath.replaceAll('.mp4', '_movenet_pose.json');
        await File(jsonPath).writeAsString(jsonEncode({
          'model': 'MoveNet Lightning',
          'keypoint_count': 17,
          'video_path': videoPath,
          'analyzed_at': DateTime.now().toIso8601String(),
          'frame_count': poseData.length,
          'analysis_method': 'motion_adaptive_parallel',
          'worker_count': workerCount,
          'motion_profile': motionProfile.map((s) => s.toJson()).toList(),
          'frames': poseData,
        }));

        // Backward-compatibility: Schultern-JSON
        final shoulderData = poseData.map((frame) {
          final kp = frame['keypoints'];
          return {
            'timestamp_ms': frame['timestamp_ms'],
            'left': {
              'x': kp['left_shoulder']['x'],
              'y': kp['left_shoulder']['y']
            },
            'right': {
              'x': kp['right_shoulder']['x'],
              'y': kp['right_shoulder']['y']
            },
          };
        }).toList();

        final shoulderJsonPath =
            videoPath.replaceAll('.mp4', '_shoulders.json');
        await File(shoulderJsonPath).writeAsString(jsonEncode(shoulderData));

        if (kDebugMode) {
          debugPrint('✅ Saved ${poseData.length} pose frames');

          // Performance-Stats
          final fpsDistribution = <int, int>{};
          for (final frame in poseData) {
            final fps = frame['fps_used'] as int? ?? 30;
            fpsDistribution[fps] = (fpsDistribution[fps] ?? 0) + 1;
          }
          debugPrint('📊 FPS Distribution:');
          fpsDistribution.forEach((fps, count) {
            debugPrint(
                '  ${fps}fps: $count frames (${(count / poseData.length * 100).toStringAsFixed(1)}%)');
          });
        }
      } else {
        if (kDebugMode) debugPrint('⚠️ Keine Pose erkannt!');
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Analyse fehlgeschlagen: $e');
      if (mounted) {
        try {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Analyse fehlgeschlagen: $e')),
          );
        } catch (_) {}
      }
    }
  }

  void _updateAnalysisStatus(String status, [String progress = '']) {
    _analysisStatus = status;
    _analysisProgress = progress;
    if (kDebugMode) debugPrint('📋 $status $progress');
  }

  /// Erkennt Bewegungs-Intensität und Golf-Schwung-Phasen
  Future<List<MotionSegment>> _detectMotionProfile(
    VideoPlayerController controller,
    GlobalKey repaintKey,
    int durationMs,
  ) async {
    final segments = <MotionSegment>[];
    const sampleInterval = 100; // Alle 100ms ein Sample

    Uint8List? previousFrame;
    final motionSamples = <double>[];

    // Quick-Scan durchführen
    for (int ms = 0; ms < durationMs; ms += sampleInterval) {
      await controller.seekTo(Duration(milliseconds: ms));
      await Future.delayed(Duration(milliseconds: 40));

      try {
        final renderObj = repaintKey.currentContext?.findRenderObject();
        if (renderObj is! RenderRepaintBoundary) continue;

        final boundary = renderObj as RenderRepaintBoundary;
        final ui.Image captured =
            await boundary.toImage(pixelRatio: 0.2); // Klein!
        final byteData =
            await captured.toByteData(format: ui.ImageByteFormat.rawRgba);

        if (byteData == null) continue;

        final currentFrame = byteData.buffer.asUint8List();

        double motion = 0.0;
        if (previousFrame != null &&
            previousFrame.length == currentFrame.length) {
          int totalDiff = 0;
          for (int i = 0; i < currentFrame.length; i += 16) {
            // Sample jeden 4. Pixel
            totalDiff += (currentFrame[i] - previousFrame[i]).abs();
          }
          motion = (totalDiff / (currentFrame.length / 16)) / 255.0;
        }

        motionSamples.add(motion);
        previousFrame = currentFrame;
        captured.dispose();

        // Reduziertes Status-Update (nur alle 500ms für Performance)
        if (ms % 500 == 0) {
          _updateAnalysisStatus('Phase 1: Bewegungs-Erkennung...',
              '${(ms / durationMs * 100).toStringAsFixed(0)}%');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Motion detection error: $e');
      }
    }

    // Glätte Motion-Samples (Median-Filter)
    final smoothedMotion = <double>[];
    for (int i = 0; i < motionSamples.length; i++) {
      if (i == 0 || i == motionSamples.length - 1) {
        smoothedMotion.add(motionSamples[i]);
      } else {
        final window = [
          motionSamples[i - 1],
          motionSamples[i],
          motionSamples[i + 1],
        ]..sort();
        smoothedMotion.add(window[1]); // Median
      }
    }

    // Erstelle Segmente mit Golf-Phase-Erkennung
    for (int i = 0; i < smoothedMotion.length; i++) {
      final startMs = i * sampleInterval;
      final endMs = ((i + 1) * sampleInterval).clamp(0, durationMs);
      final motion = smoothedMotion[i];

      // Erkenne Schwung-Phase basierend auf Motion
      final phase = _detectSwingPhase(motion, i, smoothedMotion);

      // Wähle FPS basierend auf Phase
      int fps;
      if (phase == SwingPhase.downswing || phase == SwingPhase.impact) {
        fps = 120; // Kritische Momente!
      } else if (phase == SwingPhase.transition ||
          phase == SwingPhase.backswing ||
          phase == SwingPhase.followThrough) {
        fps = 60; // Moderate Bewegung
      } else {
        fps = 30; // Setup, Top, Finish
      }

      segments.add(MotionSegment(
        startMs: startMs,
        endMs: endMs,
        motionLevel: motion,
        phase: phase,
        recommendedFps: fps,
      ));
    }

    // Merge ähnliche aufeinanderfolgende Segmente
    final mergedSegments = <MotionSegment>[];
    MotionSegment? current;

    for (final segment in segments) {
      if (current == null) {
        current = segment;
      } else if (current.phase == segment.phase &&
          current.recommendedFps == segment.recommendedFps) {
        // Merge
        current = MotionSegment(
          startMs: current.startMs,
          endMs: segment.endMs,
          motionLevel: (current.motionLevel + segment.motionLevel) / 2,
          phase: current.phase,
          recommendedFps: current.recommendedFps,
        );
      } else {
        mergedSegments.add(current);
        current = segment;
      }
    }
    if (current != null) mergedSegments.add(current);

    return mergedSegments;
  }

  /// Erkennt Schwung-Phase basierend auf Motion-Muster
  SwingPhase _detectSwingPhase(
      double motion, int index, List<double> allMotion) {
    // Address: Anfang, wenig Bewegung
    if (index < 5 && motion < 0.15) {
      return SwingPhase.address;
    }

    // Takeaway: Bewegung beginnt
    if (motion > 0.1 && motion < 0.4) {
      return SwingPhase.takeaway;
    }

    // Backswing: Moderate ansteigende Bewegung
    if (motion >= 0.4 && motion < 0.6) {
      return SwingPhase.backswing;
    }

    // Top: Kurze Pause (Motion sinkt kurz)
    if (index > 0 && index < allMotion.length - 1) {
      final prev = allMotion[index - 1];
      final next = allMotion[index + 1];
      if (motion < prev && motion < next && motion < 0.5) {
        return SwingPhase.top;
      }
    }

    // Transition: Kurz vor Downswing
    if (motion >= 0.6 && motion < 0.75) {
      return SwingPhase.transition;
    }

    // Downswing: Sehr hohe Bewegung
    if (motion >= 0.75 && motion < 0.9) {
      return SwingPhase.downswing;
    }

    // Impact: Peak Motion
    if (motion >= 0.9) {
      return SwingPhase.impact;
    }

    // Follow-Through: Auslaufende Bewegung
    if (motion >= 0.5 && motion < 0.75) {
      return SwingPhase.followThrough;
    }

    // Finish: Ende, abnehmende Bewegung
    return SwingPhase.finish;
  }

  /// Worker-Methode für parallele Segment-Analyse
  Future<List<Map<String, dynamic>>> _analyzeSegmentsWorker({
    required String videoPath,
    required List<MotionSegment> segments,
    required int videoWidth,
    required int videoHeight,
    required int workerIndex,
  }) async {
    final poseData = <Map<String, dynamic>>[];

    // Eigener Video-Controller für diesen Worker
    final workerController = VideoPlayerController.file(File(videoPath));
    await workerController.initialize();
    await workerController.pause();

    // Eigener Repaint-Key
    final GlobalKey workerRepaintKey = GlobalKey();

    // Eigenes Overlay
    OverlayEntry? workerOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: -10000 - (workerIndex * 2000),
        top: -10000,
        child: RepaintBoundary(
          key: workerRepaintKey,
          child: SizedBox(
            width: videoWidth.toDouble(),
            height: videoHeight.toDouble(),
            child: VideoPlayer(workerController),
          ),
        ),
      ),
    );

    if (mounted) {
      Overlay.of(context).insert(workerOverlay);
      await Future.delayed(Duration(milliseconds: 300));
    }

    int frameCount = 0;

    try {
      for (final segment in segments) {
        final fps = segment.recommendedFps;
        final msPerFrame = 1000 / fps;

        for (double frameTime = segment.startMs.toDouble();
            frameTime < segment.endMs;
            frameTime += msPerFrame) {
          final ms = frameTime.round();

          try {
            await workerController.seekTo(Duration(milliseconds: ms));
            await Future.delayed(Duration(milliseconds: 45));

            final renderObj =
                workerRepaintKey.currentContext?.findRenderObject();
            if (renderObj is! RenderRepaintBoundary) continue;

            final boundary = renderObj as RenderRepaintBoundary;
            final ui.Image captured = await boundary.toImage(pixelRatio: 1.0);
            final byteData =
                await captured.toByteData(format: ui.ImageByteFormat.rawRgba);

            if (byteData == null) continue;

            final rgba = byteData.buffer.asUint8List();
            final w = captured.width;
            final h = captured.height;

            // MoveNet Inferenz
            final cropData = _prepareMoveNetInput(rgba, w, h,
                centerCrop: true, targetSize: 192);
            final inputImage = cropData['image'] as List;
            final cropMeta = cropData['crop'] as Map<String, int>;

            // Konvertiere zu Uint8List
            final uint8Input = Uint8List(192 * 192 * 3);
            int idx = 0;
            for (int y = 0; y < 192; y++) {
              for (int x = 0; x < 192; x++) {
                for (int c = 0; c < 3; c++) {
                  uint8Input[idx++] =
                      (inputImage[y][x][c] * 255).round().clamp(0, 255);
                }
              }
            }

            final input =
                uint8Input.buffer.asUint8List().reshape([1, 192, 192, 3]);
            final output = List.generate(
                1,
                (_) => List.generate(
                    1, (_) => List.generate(17, (_) => List.filled(3, 0.0))));

            MoveNetManager.interpreter!.run(input, output);

            final rawOut = output[0][0];
            final cropX = cropMeta['x']!;
            final cropY = cropMeta['y']!;
            final cropW = cropMeta['w']!;
            final cropH = cropMeta['h']!;

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

            for (int i = 0; i < 17; i++) {
              final y = (rawOut[i][0] as double).clamp(0.0, 1.0);
              final x = (rawOut[i][1] as double).clamp(0.0, 1.0);
              final score = (rawOut[i][2] as double).clamp(0.0, 1.0);

              final double origX = (cropX + x * cropW) / w;
              final double origY = (cropY + y * cropH) / h;

              keypoints[keypointNames[i]] = {
                'x': origX,
                'y': origY,
                'score': score,
              };
            }

            final leftShoulder = keypoints['left_shoulder']!;
            final rightShoulder = keypoints['right_shoulder']!;

            if (leftShoulder['score']! >= 0.3 &&
                rightShoulder['score']! >= 0.3) {
              poseData.add({
                'timestamp_ms': ms,
                'frame_index': frameCount,
                'fps_used': fps,
                'motion_level': segment.motionLevel,
                'swing_phase': segment.phase.toString(),
                'worker_id': workerIndex,
                'keypoints': keypoints,
              });
              frameCount++;

              // Reduziertes Logging für Performance (nur jedes 30. Frame)
              if (kDebugMode && frameCount % 30 == 0) {
                debugPrint('⚡ Worker $workerIndex: $frameCount frames');
              }
            }

            captured.dispose();
          } catch (e) {
            if (kDebugMode)
              debugPrint('Worker $workerIndex error at ${ms}ms: $e');
          }
        }

        // Progress Update (reduziert für Performance - nur alle 20%)
        if (mounted &&
            segments.indexOf(segment) % (segments.length ~/ 5).clamp(1, 999) ==
                0) {
          final progress = (segments.indexOf(segment) / segments.length * 100)
              .toStringAsFixed(0);
          _updateAnalysisStatus(
              'Phase 2: Worker $workerIndex...', '$progress%');
        }
      }
    } finally {
      workerOverlay.remove();
      await workerController.dispose();
    }

    if (kDebugMode) {
      debugPrint('Worker $workerIndex: Analyzed $frameCount frames');
    }

    return poseData;
  }
}

class CameraSmokeTestScreen extends StatefulWidget {
  const CameraSmokeTestScreen({super.key});

  @override
  State<CameraSmokeTestScreen> createState() => _CameraSmokeTestScreenState();
}

bool _isImagePath(String p) {
  final lower = p.toLowerCase();
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.bmp') ||
      lower.endsWith('.webp');
}

class PhotoReviewScreen extends StatefulWidget {
  final String photoPath;
  final int swingNumber;

  const PhotoReviewScreen(
      {required this.photoPath, this.swingNumber = 1, super.key});

  @override
  State<PhotoReviewScreen> createState() => _PhotoReviewScreenState();
}

class _PhotoReviewScreenState extends State<PhotoReviewScreen> {
  final Set<Issue> _selected = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Swing ${widget.swingNumber}: Photo Review')),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  Expanded(
                      child: Image.file(File(widget.photoPath),
                          fit: BoxFit.contain)),
                  const SizedBox(height: 8),
                  const Text('Markiere Auffälligkeiten',
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        children: Issue.values.map((issue) {
                          return CheckboxListTile(
                            value: _selected.contains(issue),
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _selected.add(issue);
                                } else {
                                  _selected.remove(issue);
                                }
                              });
                            },
                            title: Text(issueTitle(issue)),
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).pop<Set<Issue>>(<Issue>{}),
                      child: const Text('Verwerfen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.of(context).pop<Set<Issue>>(_selected),
                      child: const Text('Speichern'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraSmokeTestScreenState extends State<CameraSmokeTestScreen> {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  bool _isRecording = false;

  bool _loading = true;
  String? _error;
  String? _lastSavedPath;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
      _lastSavedPath = null;
    });

    try {
      final cams = await availableCameras();
      // Debug: print available cameras for diagnosis
      try {
        if (kDebugMode)
          debugPrint('DEBUG: availableCameras returned ${cams.length} devices');
        for (var i = 0; i < cams.length; i++) {
          final cam = cams[i];
          if (kDebugMode)
            debugPrint(
                'DEBUG: camera[$i] name=${cam.name} lens=${cam.lensDirection} orientation=${cam.sensorOrientation}');
        }
      } catch (_) {}

      // Prefer an "internal" / integrated camera if available. Heuristic:
      // 1) name contains integrated|internal|built-in|builtin
      // 2) else prefer devices that do NOT mention 'usb' (external webcams often show USB)
      // 3) fallback to first camera
      CameraDescription? preferred;
      try {
        preferred = cams.firstWhere((c) {
          final n = c.name.toLowerCase();
          return n.contains('integrated') ||
              n.contains('internal') ||
              n.contains('built-in') ||
              n.contains('builtin');
        });
      } catch (_) {
        try {
          preferred =
              cams.firstWhere((c) => !c.name.toLowerCase().contains('usb'));
        } catch (_) {
          preferred = cams.isNotEmpty ? cams.first : null;
        }
      }
      if (!mounted) return;

      setState(() {
        // expose only the preferred/internal camera to the UI
        _cameras = preferred != null ? [preferred] : cams;
      });

      if (cams.isEmpty) {
        setState(() {
          _error = 'Keine Kamera gefunden.\n\nCheckliste:\n'
              '1) camera + camera_windows im pubspec?\n'
              '2) Teams/Browser/OBS geschlossen?\n'
              '3) Windows Kamera-App funktioniert?\n'
              '4) Windows N? Media Feature Pack installieren.\n';
          _loading = false;
        });
        return;
      }

      await _selectCamera(cams.first);
      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    } catch (e) {
      try {
        if (kDebugMode) debugPrint('ERROR: availableCameras failed: $e');
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _error = 'Kamera-Init fehlgeschlagen: $e';
        _loading = false;
      });
    }
  }

  Future<void> _startRecording() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      // Ensure MoveNet is initialized when recording starts so per-frame analysis can run during capture.
      try {
        await MoveNetManager.init();
        if (kDebugMode)
          debugPrint(
              'MoveNet init called from _startRecording; interpreter loaded=${MoveNetManager.interpreter != null}');
      } catch (e) {
        if (kDebugMode)
          debugPrint('MoveNet init failed at recording start: $e');
      }
      await c.startVideoRecording();
      setState(() {
        _isRecording = true;
        _lastSavedPath = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Start recording failed: $e';
      });
    }
  }

  Future<void> _stopRecording() async {
    final c = _controller;
    if (c == null) return;
    try {
      final xfile = await c.stopVideoRecording();
      final dir = await getApplicationDocumentsDirectory();
      final outDir = Directory('${dir.path}\\smart_range_coach');
      if (!await outDir.exists()) await outDir.create(recursive: true);
      final savedPath =
          '${outDir.path}\\video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      await File(xfile.path).copy(savedPath);

      // Video analysieren
      if (mounted) {
        await _analyzeVideoAndSaveShoulders(savedPath);
      }

      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _lastSavedPath = savedPath;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _error = 'Stop recording failed: $e';
      });
    }
  }

  Future<void> _analyzeVideoAndSaveShoulders(String videoPath) async {
    try {
      if (!mounted) return;

      // Progress-Dialog anzeigen
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Analysiere mit MoveNet...'),
              SizedBox(height: 8),
              Text('17 Keypoints werden erkannt',
                  style: TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
        ),
      );

      // MoveNet initialisieren
      await MoveNetManager.init();

      // Video-Controller
      final tempController = VideoPlayerController.file(File(videoPath));
      await tempController.initialize();
      await tempController.pause();

      List<Map<String, dynamic>> poseData = [];
      final duration = tempController.value.duration;
      final videoWidth = tempController.value.size.width.toInt();
      final videoHeight = tempController.value.size.height.toInt();

      if (kDebugMode)
        debugPrint(
            'Video: ${videoWidth}x${videoHeight}, ${duration.inMilliseconds}ms');

      // Overlay für Frame-Capture
      final GlobalKey repaintKey = GlobalKey();
      OverlayEntry? overlayEntry;

      overlayEntry = OverlayEntry(
        builder: (context) => Positioned(
          left: -10000,
          top: -10000,
          child: RepaintBoundary(
            key: repaintKey,
            child: SizedBox(
              width: videoWidth.toDouble(),
              height: videoHeight.toDouble(),
              child: VideoPlayer(tempController),
            ),
          ),
        ),
      );

      Overlay.of(context).insert(overlayEntry);
      await Future.delayed(Duration(milliseconds: 500));

      // Frame-by-Frame Analyse mit MoveNet (120fps = 8.33ms)
      int frameCount = 0;
      final estimatedFps = 120;
      final msPerFrame = 1000 / estimatedFps;

      if (kDebugMode)
        debugPrint(
            '📊 Video FPS: ~$estimatedFps, ${msPerFrame.toStringAsFixed(2)}ms pro Frame');

      for (double frameTime = 0;
          frameTime < duration.inMilliseconds;
          frameTime += msPerFrame) {
        final ms = frameTime.round();

        try {
          await tempController.seekTo(Duration(milliseconds: ms));
          await Future.delayed(Duration(milliseconds: 50));

          // Capture Frame
          final renderObj = repaintKey.currentContext?.findRenderObject();
          if (renderObj is! RenderRepaintBoundary) continue;

          final boundary = renderObj;
          final ui.Image captured = await boundary.toImage(pixelRatio: 1.0);
          final byteData =
              await captured.toByteData(format: ui.ImageByteFormat.rawRgba);

          if (byteData == null) continue;

          final rgba = byteData.buffer.asUint8List();
          final w = captured.width;
          final h = captured.height;

          // MoveNet Inferenz
          final cropData = _prepareMoveNetInput(rgba, w, h,
              centerCrop: true, targetSize: 192);
          final inputImage = cropData['image'] as List;
          final cropMeta = cropData['crop'] as Map<String, int>;

          // Konvertiere zu Uint8List für TFLite
          final Uint8List uint8Input = Uint8List(192 * 192 * 3);
          int idx = 0;
          for (int y = 0; y < 192; y++) {
            for (int x = 0; x < 192; x++) {
              for (int c = 0; c < 3; c++) {
                uint8Input[idx++] =
                    (inputImage[y][x][c] * 255).round().clamp(0, 255);
              }
            }
          }

          final input =
              uint8Input.buffer.asUint8List().reshape([1, 192, 192, 3]);
          final output = List.generate(
              1,
              (_) => List.generate(
                  1, (_) => List.generate(17, (_) => List.filled(3, 0.0))));
          MoveNetManager.interpreter!.run(input, output);

          final rawOut = output[0][0];
          final cropX = cropMeta['x']!;
          final cropY = cropMeta['y']!;
          final cropW = cropMeta['w']!;
          final cropH = cropMeta['h']!;

          // Remap Keypoints
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

          for (int i = 0; i < 17; i++) {
            final y = (rawOut[i][0] as double).clamp(0.0, 1.0);
            final x = (rawOut[i][1] as double).clamp(0.0, 1.0);
            final score = (rawOut[i][2] as double).clamp(0.0, 1.0);

            final double origX = (cropX + x * cropW) / w;
            final double origY = (cropY + y * cropH) / h;

            keypoints[keypointNames[i]] = {
              'x': origX,
              'y': origY,
              'score': score,
            };
          }

          // Speichere wenn Schultern sichtbar
          final leftShoulder = keypoints['left_shoulder']!;
          final rightShoulder = keypoints['right_shoulder']!;

          if (leftShoulder['score']! >= 0.3 && rightShoulder['score']! >= 0.3) {
            poseData.add({
              'timestamp_ms': ms,
              'frame_index': frameCount,
              'keypoints': keypoints,
            });
            frameCount++;

            if (kDebugMode && frameCount % 30 == 0) {
              debugPrint(
                  '✅ Analyzed $frameCount frames... (${(ms / duration.inMilliseconds * 100).toStringAsFixed(1)}%)');
            }
          }

          captured.dispose();
        } catch (e) {
          if (kDebugMode) debugPrint('Frame error at ${ms}ms: $e');
        }
      }

      // Cleanup
      overlayEntry.remove();
      await tempController.dispose();

      // Speichere vollständige Pose-Daten
      if (poseData.isNotEmpty) {
        final jsonPath = videoPath.replaceAll('.mp4', '_movenet_pose.json');
        await File(jsonPath).writeAsString(jsonEncode({
          'video_path': videoPath,
          'analyzed_at': DateTime.now().toIso8601String(),
          'frame_count': frameCount,
          'model': 'MoveNet Lightning',
          'frames': poseData,
        }));

        // Extrahiere Schultern für Backward-Compatibility
        final shoulderData = poseData.map((frame) {
          final kp = frame['keypoints'];
          return {
            'timestamp_ms': frame['timestamp_ms'],
            'left': {
              'x': kp['left_shoulder']['x'],
              'y': kp['left_shoulder']['y'],
            },
            'right': {
              'x': kp['right_shoulder']['x'],
              'y': kp['right_shoulder']['y'],
            },
          };
        }).toList();

        final shoulderJsonPath =
            videoPath.replaceAll('.mp4', '_shoulders.json');
        await File(shoulderJsonPath).writeAsString(jsonEncode(shoulderData));

        if (kDebugMode) debugPrint('Saved $frameCount pose frames to JSON');
      } else {
        if (kDebugMode) debugPrint('Keine Pose erkannt!');
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Analyse fehlgeschlagen: $e');
      if (mounted) {
        try {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Analyse fehlgeschlagen: $e')),
          );
        } catch (_) {}
      }
    }
  }

  Future<void> _selectCamera(CameraDescription cam) async {
    await _controller?.dispose();

    final controller = CameraController(
      cam,
      ResolutionPreset.low, // Reduzierte Auflösung für bessere Performance
      enableAudio: false,
    );

    setState(() {
      _controller = controller;
      _error = null;
      _lastSavedPath = null;
    });

    try {
      await controller.initialize();
    } catch (e) {
      setState(() {
        _error = 'CameraController.initialize() fehlgeschlagen: $e';
      });
    }

    if (mounted) setState(() {});
  }

  Future<void> _takePhoto() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final outDir = Directory('${dir.path}\\smart_range_coach');
      if (!await outDir.exists()) await outDir.create(recursive: true);

      final filePath =
          '${outDir.path}\\photo_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final xfile = await c.takePicture();
      await File(xfile.path).copy(filePath);

      if (!mounted) return;
      setState(() {
        _lastSavedPath = filePath;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'takePicture() fehlgeschlagen: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Range Coach – Camera Smoke Test'),
        actions: [
          IconButton(
            onPressed: _init,
            tooltip: 'Neu laden',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () {
              if (_lastSavedPath != null) {
                final lp = _lastSavedPath!;
                if (_isImagePath(lp)) {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          PhotoReviewScreen(photoPath: lp, swingNumber: 1)));
                } else {
                  // treat as video (mp4/mov/etc.) and open video review screen
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => SwingQuickReviewScreen(
                          videoPath: lp, swingNumber: 1)));
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Kein gespeichertes Foto/Video verfügbar')));
              }
            },
            tooltip: 'Review (Foto/Video)',
            icon: const Icon(Icons.rate_review),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gefundene Kameras: ${_cameras.length}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_cameras.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _cameras.map((cam) {
                        final label = '${cam.name} (${cam.lensDirection.name})';
                        return OutlinedButton(
                          onPressed: () => _selectCamera(cam),
                          child: Text(label),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha((0.15 * 255).round()),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.red.withAlpha((0.4 * 255).round())),
                      ),
                      child: Text(_error!, style: const TextStyle(height: 1.3)),
                    ),
                  const SizedBox(height: 16),
                  Expanded(
                    child:
                        (controller != null && controller.value.isInitialized)
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: AspectRatio(
                                  aspectRatio: controller.value.aspectRatio,
                                  child: CameraPreview(controller),
                                ),
                              )
                            : Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Center(
                                  child: Text('Keine Preview verfügbar'),
                                ),
                              ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: (controller != null &&
                                controller.value.isInitialized)
                            ? _takePhoto
                            : null,
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('Test-Foto'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: (controller != null &&
                                controller.value.isInitialized)
                            ? (_isRecording ? _stopRecording : _startRecording)
                            : null,
                        icon: Icon(_isRecording ? Icons.stop : Icons.videocam,
                            color: _isRecording ? Colors.redAccent : null),
                        label:
                            Text(_isRecording ? 'Stopp Aufnahme' : 'Aufnahme'),
                      ),
                      const SizedBox(width: 12),
                      if (_lastSavedPath != null)
                        Expanded(
                          child: Text(
                            'Gespeichert: $_lastSavedPath',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

// ========== MoveNet Hilfsmethoden (Top-Level) ==========

/// Bereitet RGBA-Bild für MoveNet vor (192x192, center crop, normalisiert)
Map<String, dynamic> _prepareMoveNetInput(
  Uint8List rgba,
  int width,
  int height, {
  bool centerCrop = true,
  int targetSize = 192,
}) {
  // Center Crop Berechnung
  int cropX = 0, cropY = 0, cropW = width, cropH = height;

  if (centerCrop) {
    if (width > height) {
      cropW = height;
      cropX = (width - height) ~/ 2;
    } else {
      cropH = width;
      cropY = (height - width) ~/ 2;
    }
  }

  // Resize zu targetSize x targetSize und normalisiere
  final resized = List.generate(
    targetSize,
    (y) => List.generate(
      targetSize,
      (x) {
        final srcX = cropX + (x * cropW / targetSize).floor();
        final srcY = cropY + (y * cropH / targetSize).floor();
        final idx = (srcY * width + srcX) * 4;

        return [
          rgba[idx] / 255.0, // R
          rgba[idx + 1] / 255.0, // G
          rgba[idx + 2] / 255.0, // B
        ];
      },
    ),
  );

  return {
    'image': resized,
    'crop': {'x': cropX, 'y': cropY, 'w': cropW, 'h': cropH},
  };
}
