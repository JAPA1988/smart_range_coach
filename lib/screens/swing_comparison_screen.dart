import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../models/pose_frame.dart' as pose;
import '../models/user_swing.dart' as user;
import '../widgets/pro_projection_raster_view.dart';

class KeyPositionEntry {
  final String position;
  final String imagePath;
  final String rasterPath;
  final int timestampMs;
  final int frameIndex;
  final double qualityScore;
  final Map<String, dynamic> keypoints;

  KeyPositionEntry({
    required this.position,
    required this.imagePath,
    required this.rasterPath,
    required this.timestampMs,
    required this.frameIndex,
    required this.qualityScore,
    required this.keypoints,
  });
}

class SwingComparisonScreen extends StatefulWidget {
  final user.UserSwing userSwing;

  const SwingComparisonScreen({super.key, required this.userSwing});

  @override
  State<SwingComparisonScreen> createState() => _SwingComparisonScreenState();
}

class _SwingComparisonScreenState extends State<SwingComparisonScreen> {
  static const List<String> _positionOrder = [
    'address',
    'takeaway',
    'set_position',
    'top_position',
    'downswing',
    'impact',
    'follow_through',
  ];

  static const Map<String, String> _positionTitles = {
    'address': 'Address',
    'takeaway': 'Takeaway',
    'set_position': 'Set-Position',
    'top_position': 'Top Position',
    'downswing': 'Downswing',
    'impact': 'Impact',
    'follow_through': 'Follow Through',
  };

  bool _loading = true;
  bool _showRaster = false;
  bool _showSpineMarker = false;
  bool _showHipOverAnkleMarker = false;
  bool _showShoulderOverHandMarker = false;
  bool _showKneeFlexMarker = false;

  double? _userVideoAspect;

  String? _selectedPosition;
  final Map<String, KeyPositionEntry> _entries = {};

  @override
  void initState() {
    super.initState();
    _loadEntries();
    _loadUserVideoAspect();
  }

  String _swingIdFromVideoPath(String videoPath) {
    return videoPath.split(Platform.pathSeparator).last.replaceAll('.mp4', '');
  }

  Future<void> _loadUserVideoAspect() async {
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(File(widget.userSwing.videoPath));
      await controller.initialize();
      final size = controller.value.size;
      if (size.height > 0 && mounted) {
        setState(() {
          _userVideoAspect = size.width / size.height;
        });
      }
    } catch (_) {
    } finally {
      await controller?.dispose();
    }
  }

  Future<void> _loadEntries() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final outDir = Directory(
          '${dir.path}${Platform.pathSeparator}smart_range_coach${Platform.pathSeparator}key_positions');
      if (!await outDir.exists()) {
        setState(() => _loading = false);
        return;
      }

      final swingId = _swingIdFromVideoPath(widget.userSwing.videoPath);
      final files = await outDir.list().toList();

      for (final entity in files) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.startsWith('${swingId}_') || !name.endsWith('.json')) {
          continue;
        }

        final raw = await entity.readAsString();
        final doc = jsonDecode(raw) as Map<String, dynamic>;
        final position = doc['position'] as String? ?? '';
        if (position.isEmpty) continue;

        _entries[position] = KeyPositionEntry(
          position: position,
          imagePath: doc['image_path'] as String? ?? '',
          rasterPath: doc['raster_path'] as String? ?? '',
          timestampMs: doc['timestamp_ms'] as int? ?? 0,
          frameIndex: doc['frame_index'] as int? ?? -1,
          qualityScore: (doc['quality_score'] as num?)?.toDouble() ?? 0.0,
          keypoints: Map<String, dynamic>.from(doc['keypoints'] ?? {}),
        );
      }

      if (_entries.isNotEmpty) {
        _selectedPosition = _positionOrder
            .firstWhere((pos) => _entries.containsKey(pos), orElse: () => '');
        if (_selectedPosition!.isEmpty) {
          _selectedPosition = _entries.keys.first;
        }
      }
    } catch (_) {
      // noop
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  pose.PoseFrame _poseFromKeypoints(KeyPositionEntry entry) {
    final keypoints = <String, pose.Keypoint>{};
    for (final item in entry.keypoints.entries) {
      final raw = Map<String, dynamic>.from(item.value as Map);
      final x = (raw['x'] as num?)?.toDouble() ?? 0.0;
      final y = (raw['y'] as num?)?.toDouble() ?? 0.0;
      final score = (raw['score'] as num?)?.toDouble() ?? 0.0;
      keypoints[item.key] = pose.Keypoint(
        label: item.key,
        x: x,
        y: y,
        confidence: score,
      );
    }

    return pose.PoseFrame(
      timestamp: Duration(milliseconds: entry.timestampMs),
      frameIndex: entry.frameIndex,
      keypoints: keypoints,
      qualityScore: entry.qualityScore,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected =
        _selectedPosition != null ? _entries[_selectedPosition] : null;

    final aspect = _userVideoAspect ?? (16 / 9);

    return Scaffold(
      appBar: AppBar(title: const Text('Swing Review')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(child: Text('Keine Key Positions gefunden.'))
              : SingleChildScrollView(
                  child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Text('Position:'),
                          const SizedBox(width: 12),
                          DropdownButton<String>(
                            value: _selectedPosition,
                            items: _positionOrder
                                .where((pos) => _entries.containsKey(pos))
                                .map((pos) {
                              return DropdownMenuItem<String>(
                                value: pos,
                                child: Text(_positionTitles[pos] ?? pos),
                              );
                            }).toList(),
                            onChanged: (v) {
                              setState(() {
                                _selectedPosition = v;
                              });
                            },
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              const Text('Raster'),
                              Switch(
                                value: _showRaster,
                                onChanged: (v) {
                                  setState(() => _showRaster = v);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_showRaster)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            _markerToggle(
                              'Spine 38�/45�',
                              _showSpineMarker,
                              (v) => setState(() => _showSpineMarker = v),
                            ),
                            _markerToggle(
                              'H�fte �ber Kn�chel',
                              _showHipOverAnkleMarker,
                              (v) =>
                                  setState(() => _showHipOverAnkleMarker = v),
                            ),
                            _markerToggle(
                              'Schulter �ber H�nde',
                              _showShoulderOverHandMarker,
                              (v) => setState(
                                  () => _showShoulderOverHandMarker = v),
                            ),                            _markerToggle(
                              'Knee Flex 170°',
                              _showKneeFlexMarker,
                              (v) => setState(() => _showKneeFlexMarker = v),
                            ),                          ],
                        ),
                      ),
                    if (selected != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'Frame: ${selected.frameIndex} � '
                          'Zeit: ${selected.timestampMs}ms � '
                          'Quality: ${(selected.qualityScore * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Container(
                      margin: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: selected == null
                          ? const Center(child: Text('Keine Auswahl'))
                          : AspectRatio(
                              aspectRatio: aspect,
                              child: _showRaster
                                  ? _buildRasterView(selected)
                                  : Image.file(
                                      File(selected.imagePath),
                                      fit: BoxFit.contain,
                                    ),
                            ),
                    ),
                    if (_showRaster && selected != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        child: _buildMetricsRow(_poseFromKeypoints(selected)),
                      ),
                  ],
                ),
                ),
    );
  }

  Widget _markerToggle(
      String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(
          value: value,
          onChanged: onChanged,
        ),
        Text(label),
      ],
    );
  }

  Widget _buildRasterView(KeyPositionEntry selected) {
    final poseFrame = _poseFromKeypoints(selected);

    return Stack(
      children: [
        Positioned.fill(
          child: ProProjectionRasterView(
            poseFrame: poseFrame,
            sideCropCm: 0.0,
            rightHalfOnly: false,
            projectionShiftX: 0.0,
            projectionShiftCm: 0.0,
            showGrid: true,
            showSpineAngleMarker: false,
            minConfidence: 0.35,
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _UserMarkerPainter(
              poseFrame: poseFrame,
              showSpineMarker: _showSpineMarker,
              showHipOverAnkleMarker: _showHipOverAnkleMarker,
              showShoulderOverHandMarker: _showShoulderOverHandMarker,
              showKneeFlexMarker: _showKneeFlexMarker,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricsRow(pose.PoseFrame poseFrame) {
    final spine = _spineAngle(poseFrame);
    final kneeFlex = _kneeFlexRight(poseFrame);

    String fmt(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}°';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Text('Spine Angle: ${fmt(spine)}'),
        Text('Knee Flex: ${fmt(kneeFlex)}'),
      ],
    );
  }

  double? _spineAngle(pose.PoseFrame frame) {
    final hip = frame.getKeypoint('right_hip');
    final shoulder = frame.getKeypoint('right_shoulder');
    if (hip == null || shoulder == null || !hip.isVisible || !shoulder.isVisible) {
      return null;
    }
    final dx = hip.x - shoulder.x;
    final dy = hip.y - shoulder.y;
    if (dx == 0 && dy == 0) return null;
    return (math.atan2(dx, dy).abs()) * 180 / math.pi;
  }

  double? _kneeFlexRight(pose.PoseFrame frame) {
    final hip = frame.getKeypoint('right_hip');
    final knee = frame.getKeypoint('right_knee');
    final ankle = frame.getKeypoint('right_ankle');
    if (hip == null ||
        knee == null ||
        ankle == null ||
        !hip.isVisible ||
        !knee.isVisible ||
        !ankle.isVisible) {
      return null;
    }
    final angle = _angleBetween(
      Offset(hip.x, hip.y),
      Offset(knee.x, knee.y),
      Offset(ankle.x, ankle.y),
    );
    if (angle == null) return null;
    return 180.0 - angle;
  }

  double? _angleBetween(Offset a, Offset b, Offset c) {
    final ab = a - b;
    final cb = c - b;
    final dot = ab.dx * cb.dx + ab.dy * cb.dy;
    final mag = ab.distance * cb.distance;
    if (mag == 0) return null;
    final cos = (dot / mag).clamp(-1.0, 1.0);
    return math.acos(cos) * 180 / math.pi;
  }
}

class _UserMarkerPainter extends CustomPainter {
  final pose.PoseFrame poseFrame;
  final bool showSpineMarker;
  final bool showHipOverAnkleMarker;
  final bool showShoulderOverHandMarker;
  final bool showKneeFlexMarker;

  _UserMarkerPainter({
    required this.poseFrame,
    required this.showSpineMarker,
    required this.showHipOverAnkleMarker,
    required this.showShoulderOverHandMarker,
    required this.showKneeFlexMarker,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    Offset? kp(String label) {
      final k = poseFrame.getKeypoint(label);
      if (k == null || !k.isVisible) return null;
      return Offset(k.x * size.width, k.y * size.height);
    }

    if (showSpineMarker) {
      final hip = kp('right_hip');
      final shoulder = kp('right_shoulder');
      if (hip != null) {
        // Schablone 38° / 45°
        _drawSpineLine(canvas, paint, hip, size, 38);
        _drawSpineLine(canvas, paint, hip, size, 45);

        // User‑Spine‑Line (blau, 2 cm, Richtung Schulter)
        if (shoulder != null) {
          final userPaint = Paint()
            ..color = Colors.blue
            ..strokeWidth = 3
            ..style = PaintingStyle.stroke;
          _drawUserSpineLine(canvas, userPaint, hip, shoulder);
        }
      }
    }

    if (showHipOverAnkleMarker) {
      final hip = kp('right_hip');
      final ankle = kp('right_ankle');
      if (hip != null && ankle != null) {
        final end = Offset(hip.dx, ankle.dy);
        canvas.drawLine(hip, end, paint);
      }
    }

    if (showShoulderOverHandMarker) {
      final shoulder = kp('right_shoulder');
      final wrist = kp('right_wrist');
      if (shoulder != null && wrist != null) {
        final end = Offset(shoulder.dx, wrist.dy);
        canvas.drawLine(shoulder, end, paint);
      }
    }

    if (showKneeFlexMarker) {
      final knee = kp('right_knee');
      if (knee != null) {
        _drawKneeFlexTemplate(canvas, paint, knee, size);
      }
    }
  }

  void _drawSpineLine(
      Canvas canvas, Paint paint, Offset hip, Size size, double deg) {
    final angle = deg * math.pi / 180;

    // 2 cm in logical px
    const logicalPixelsPerInch = 160.0;
    final length = (2 / 2.54) * logicalPixelsPerInch;

    final end = Offset(
      hip.dx + length * math.sin(angle), // nach rechts
      hip.dy - length * math.cos(angle), // nach oben
    );

    canvas.drawLine(hip, end, paint);
  }

  void _drawUserSpineLine(
      Canvas canvas, Paint paint, Offset hip, Offset shoulder) {
    final dx = shoulder.dx - hip.dx;
    final dy = shoulder.dy - hip.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist == 0) return;

    // 2 cm in logical px
    const logicalPixelsPerInch = 160.0;
    final length = (2 / 2.54) * logicalPixelsPerInch;

    final nx = dx / dist;
    final ny = dy / dist;

    final end = Offset(
      hip.dx + nx * length,
      hip.dy + ny * length,
    );

    canvas.drawLine(hip, end, paint);
  }

  void _drawKneeFlexTemplate(
      Canvas canvas, Paint paint, Offset knee, Size size) {
    const angleDeg = 165.0;
    final halfAngle = (angleDeg / 2) * math.pi / 180;

    // 1 cm in logical px (wie im Raster verwendet)
    const logicalPixelsPerInch = 160.0;
    final length = (1 / 2.54) * logicalPixelsPerInch;

    // Horizontale Richtung nach rechts, symmetrisch nach oben/unten
    final dx = math.cos(halfAngle) * length;
    final dy = math.sin(halfAngle) * length;

    final endUp = Offset(knee.dx + dx, knee.dy - dy);
    final endDown = Offset(knee.dx + dx, knee.dy + dy);

    canvas.drawLine(knee, endUp, paint);
    canvas.drawLine(knee, endDown, paint);
  }

  @override
  bool shouldRepaint(covariant _UserMarkerPainter oldDelegate) => true;
}
