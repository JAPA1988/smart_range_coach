import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../screens/comparison_movenet_data_screen.dart';
import '../models/pose_frame.dart' as pose;
import '../models/reference_swing.dart' as ref;
import '../models/user_swing.dart' as user;
import '../services/reference_swing_service.dart';
import '../widgets/pose_overlay_painter.dart';

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

class SwingComparisonScreen extends StatefulWidget {
  final user.UserSwing userSwing;

  const SwingComparisonScreen({super.key, required this.userSwing});

  @override
  State<SwingComparisonScreen> createState() => _SwingComparisonScreenState();
}

class _SwingComparisonScreenState extends State<SwingComparisonScreen> {
  List<ref.ReferenceSwing>? _proSwings;
  ref.ReferenceSwing? _selectedProSwing;
  String _selectedPosition = 'address';
  bool _loading = true;
  String? _error;
  bool _showSpineMarker = true;
  bool _showHipOverAnkleMarker = true;
  bool _showShoulderOverHandMarker = true;
  bool _showKneeFlexMarker = true;

  static const double _minScale = 0.7;
  static const double _maxScale = 2.2;

  final List<String> _positions = [
    'address',
    'takeaway',
    'set_position',
    'top_position',
    'downswing',
    'impact',
    'follow_through',
  ];

  @override
  void initState() {
    super.initState();
    _loadProSwings();
  }

  Future<void> _loadProSwings() async {
    try {
      final service = ReferenceSwingService();
      final swings = await service.loadAllSwings();
      if (!mounted) return;
      setState(() {
        _proSwings = swings;
        _selectedProSwing = swings.isNotEmpty ? swings.first : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load pro swings: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Comparison')),
        body: Center(child: Text(_error!)),
      );
    }

    if (_selectedProSwing == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Comparison')),
        body: const Center(child: Text('No pro swings available')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Swing Comparison'),
      ),
      body: Column(
        children: [
          _buildProSwingSelector(),
          _buildDataScreenButton(),
          Expanded(child: _buildSideBySideComparison()),
        ],
      ),
    );
  }

  Widget _buildRasterFrame({
    required double width,
    required double height,
    required Widget child,
  }) {
    return AspectRatio(
      aspectRatio: width / height,
      child: SizedBox(
        width: width,
        height: height,
        child: child,
      ),
    );
  }

  Widget _buildProSwingSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.blue[50],
      child: Row(
        children: [
          const Text('Compare with: ',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<ref.ReferenceSwing>(
              value: _selectedProSwing,
              isExpanded: true,
              items: _proSwings!.map((swing) {
                return DropdownMenuItem(
                  value: swing,
                  child: Text('${swing.golferName} (${swing.clubType})'),
                );
              }).toList(),
              onChanged: (swing) {
                setState(() => _selectedProSwing = swing);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPositionSelector() {
    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _positions.length,
        itemBuilder: (context, index) {
          final position = _positions[index];
          final isSelected = position == _selectedPosition;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(_formatPositionName(position)),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedPosition = position);
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildSideBySideComparison() {
    final userPositions = _effectiveUserPositions();
    final userPosition = userPositions[_selectedPosition];
    final proPosition = _selectedProSwing!.positions[_selectedPosition];
    final proVideo = _selectedProSwing!.videoInfo;

    if (userPosition == null || proPosition == null) {
      return const Center(child: Text('Position data not available'));
    }

    final userPose = _userToPoseFrame(userPosition);
    final proPose = _proToPoseFrame(proPosition);
    final scaledProPose = _scalePoseToMatch(proPose, userPose);

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              // User
              Expanded(
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Your Swing',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              color: Colors.black,
                              child: _buildRasterFrame(
                                width: proVideo.width.toDouble(),
                                height: proVideo.height.toDouble(),
                                child: userPosition.skeletonImagePath != null
                                    ? Image.file(
                                        File(userPosition.skeletonImagePath!),
                                        fit: BoxFit.contain,
                                      )
                                    : Stack(
                                        children: [
                                          Positioned.fill(
                                            child: CustomPaint(
                                                painter:
                                                    _ComparisonGridPainter()),
                                          ),
                                          Positioned.fill(
                                            child: CustomPaint(
                                              painter: PoseOverlayPainter(
                                                  userPose),
                                            ),
                                          ),
                                          Positioned.fill(
                                            child: CustomPaint(
                                              painter: _UserMarkerPainter(
                                                userPose: userPose,
                                                proPose: proPose,
                                                showSpineMarker:
                                                    _showSpineMarker,
                                                showHipOverAnkleMarker:
                                                    _showHipOverAnkleMarker,
                                                showShoulderOverHandMarker:
                                                    _showShoulderOverHandMarker,
                                                showKneeFlexMarker:
                                                    _showKneeFlexMarker,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 160,
                            child: _buildMarkerPanel(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 2, color: Colors.grey[400]),
              // Pro
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        _selectedProSwing!.golferName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        color: Colors.black,
                        child: _buildRasterFrame(
                          width: proVideo.width.toDouble(),
                          height: proVideo.height.toDouble(),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child:
                                    CustomPaint(painter: _ComparisonGridPainter()),
                              ),
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: PoseOverlayPainter(
                                    scaledProPose,
                                    requireBodyPresence: false,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _buildPositionSelector(),
        if (_selectedPosition == 'address') _buildMetricsTable(userPose, proPose),
      ],
    );
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

  double? _lineAngle(Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    if (dx == 0 && dy == 0) return null;
    return math.atan2(dy, dx) * 180 / math.pi;
  }

  Offset? _kp(pose.PoseFrame frame, String label) {
    final kp = frame.getKeypoint(label);
    if (kp == null || !kp.isVisible) return null;
    return Offset(kp.x, kp.y);
  }

  double? _kneeFlexRight(pose.PoseFrame frame) {
    final hip = _kp(frame, 'right_hip');
    final knee = _kp(frame, 'right_knee');
    final ankle = _kp(frame, 'right_ankle');
    if (hip == null || knee == null || ankle == null) return null;
    final kneeAngle = _angleBetween(hip, knee, ankle);
    if (kneeAngle == null) return null;
    return 180.0 - kneeAngle;
  }

  double? _spineAngle(pose.PoseFrame frame) {
    final hipL = _kp(frame, 'left_hip');
    final hipR = _kp(frame, 'right_hip');
    final shL = _kp(frame, 'left_shoulder');
    final shR = _kp(frame, 'right_shoulder');
    if (hipL == null || hipR == null || shL == null || shR == null) return null;

    final hipMid = Offset((hipL.dx + hipR.dx) / 2, (hipL.dy + hipR.dy) / 2);
    final shMid = Offset((shL.dx + shR.dx) / 2, (shL.dy + shR.dy) / 2);

    final dy = hipMid.dy - shMid.dy;
    final dx = hipMid.dx - shMid.dx;
    if (dy == 0 && dx == 0) return null;

    return (math.atan2(dx, dy).abs()) * 180 / math.pi;
  }

  double? _shoulderVsHipAngle(pose.PoseFrame frame) {
    final shL = _kp(frame, 'left_shoulder');
    final shR = _kp(frame, 'right_shoulder');
    final hipL = _kp(frame, 'left_hip');
    final hipR = _kp(frame, 'right_hip');
    if (shL == null || shR == null || hipL == null || hipR == null) return null;

    final shoulderAngle = _lineAngle(shL, shR);
    final hipAngle = _lineAngle(hipL, hipR);
    if (shoulderAngle == null || hipAngle == null) return null;

    return (shoulderAngle - hipAngle).abs();
  }

  double? _horizontalHipToAnkleRight(pose.PoseFrame frame) {
    final hip = _kp(frame, 'right_hip');
    final ank = _kp(frame, 'right_ankle');
    if (hip == null || ank == null) return null;
    return (hip.dx - ank.dx).abs() * 100;
  }

  double? _horizontalWristToShoulderRight(pose.PoseFrame frame) {
    final wr = _kp(frame, 'right_wrist');
    final sh = _kp(frame, 'right_shoulder');
    if (wr == null || sh == null) return null;
    return (wr.dx - sh.dx).abs() * 100;
  }

  Widget _buildMetricsTable(pose.PoseFrame userPose, pose.PoseFrame proPose) {
    String fmt(double? v, {int decimals = 1, String suffix = ''}) =>
        v == null ? '—' : '${v.toStringAsFixed(decimals)}$suffix';

    final rows = [
      (
        'Knee Flex (R)',
        fmt(_kneeFlexRight(userPose), suffix: '°'),
        fmt(_kneeFlexRight(proPose), suffix: '°')
      ),
      (
        'Spine Angle',
        fmt(_spineAngle(userPose), suffix: '°'),
        fmt(_spineAngle(proPose), suffix: '°')
      ),
      (
        'Shoulder vs Hip',
        fmt(_shoulderVsHipAngle(userPose), suffix: '°'),
        fmt(_shoulderVsHipAngle(proPose), suffix: '°')
      ),
      (
        'Δ Hip–Ankle (R)',
        fmt(_horizontalHipToAnkleRight(userPose), suffix: '%'),
        fmt(_horizontalHipToAnkleRight(proPose), suffix: '%')
      ),
      (
        'Δ Wrist–Shoulder (R)',
        fmt(_horizontalWristToShoulderRight(userPose), suffix: '%'),
        fmt(_horizontalWristToShoulderRight(proPose), suffix: '%')
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Address Metrics',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(2.4),
              1: FlexColumnWidth(1.1),
              2: FlexColumnWidth(1.1),
            },
            children: [
              const TableRow(children: [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('Metric',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('User',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('Pro',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ]),
              for (final row in rows)
                TableRow(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(row.$1),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(row.$2),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(row.$3),
                  ),
                ]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDataScreenButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          onPressed: _openMovenetDataScreen,
          icon: const Icon(Icons.analytics_outlined),
          label: const Text('MoveNet Daten öffnen'),
        ),
      ),
    );
  }

  Widget _buildMarkerPanel() {
    return Container(
      color: Colors.black.withOpacity(0.05),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Marker',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildMarkerToggle('Spine Angle', _showSpineMarker,
              (v) => setState(() => _showSpineMarker = v)),
          _buildMarkerToggle('Hips over Ankles', _showHipOverAnkleMarker,
              (v) => setState(() => _showHipOverAnkleMarker = v)),
          _buildMarkerToggle(
              'Shoulder over Hands',
              _showShoulderOverHandMarker,
              (v) => setState(() => _showShoulderOverHandMarker = v)),
          _buildMarkerToggle('Knee Flex', _showKneeFlexMarker,
              (v) => setState(() => _showKneeFlexMarker = v)),
        ],
      ),
    );
  }

  Widget _buildMarkerToggle(
      String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Switch(
          value: value,
          onChanged: onChanged,
        ),
        Expanded(child: Text(label)),
      ],
    );
  }

  Map<String, user.UserKeyPosition> _effectiveUserPositions() {
    final marked = widget.userSwing.markedPositions;
    if (marked != null && marked.isNotEmpty) {
      return marked;
    }

    final frames = widget.userSwing.frames;
    if (frames.isEmpty) {
      return const {};
    }

    final mapped = <String, user.UserKeyPosition>{};
    for (int i = 0; i < _positions.length; i++) {
      final position = _positions[i];
      final frameIndex = ((frames.length - 1) * (i / (_positions.length - 1)))
          .round()
          .clamp(0, frames.length - 1);
      final frame = frames[frameIndex];

      mapped[position] = user.UserKeyPosition(
        frameIndex: frame.frameIndex,
        timestampMs: frame.timestampMs,
        keypoints: frame.keypoints,
        markedAt: widget.userSwing.recordedAt,
      );
    }
    return mapped;
  }

  pose.PoseFrame _proToPoseFrame(ref.KeyPosition pos) {
    final keypoints = <String, pose.Keypoint>{};
    for (final entry in pos.keypoints.entries) {
      keypoints[entry.key] = pose.Keypoint(
        label: entry.key,
        x: entry.value.x,
        y: entry.value.y,
        confidence: entry.value.confidence,
      );
    }

    return pose.PoseFrame(
      timestamp: Duration(milliseconds: pos.timestampMs),
      frameIndex: pos.frame,
      keypoints: keypoints,
      qualityScore: 0.0,
    );
  }

  pose.PoseFrame _userToPoseFrame(user.UserKeyPosition pos) {
    final keypoints = <String, pose.Keypoint>{};
    for (final entry in pos.keypoints.entries) {
      keypoints[entry.key] = pose.Keypoint(
        label: entry.key,
        x: entry.value.x,
        y: entry.value.y,
        confidence: entry.value.confidence,
      );
    }

    return pose.PoseFrame(
      timestamp: Duration(milliseconds: pos.timestampMs),
      frameIndex: pos.frameIndex,
      keypoints: keypoints,
      qualityScore: 0.0,
    );
  }

  Rect _poseBounds(pose.PoseFrame frame) {
    const names = [
      'left_shoulder',
      'right_shoulder',
      'left_hip',
      'right_hip',
      'left_elbow',
      'right_elbow',
      'left_wrist',
      'right_wrist',
      'left_knee',
      'right_knee',
      'left_ankle',
      'right_ankle',
    ];

    double? minX, minY, maxX, maxY;
    int included = 0;

    void include(double x, double y) {
      minX = minX == null ? x : math.min(minX!, x);
      minY = minY == null ? y : math.min(minY!, y);
      maxX = maxX == null ? x : math.max(maxX!, x);
      maxY = maxY == null ? y : math.max(maxY!, y);
      included++;
    }

    for (final name in names) {
      final kp = frame.getKeypoint(name);
      if (kp == null || !kp.isVisible) continue;
      include(kp.x, kp.y);
    }

    // Fallback 1: gleiche Kernpunkte auch bei niedriger Confidence.
    if (included < 2) {
      for (final name in names) {
        final kp = frame.getKeypoint(name);
        if (kp == null) continue;
        include(kp.x, kp.y);
      }
    }

    // Fallback 2 (wichtig für Address): nutze alle verfügbaren MoveNet-Punkte.
    if (included < 2) {
      for (final kp in frame.keypoints.values) {
        if (!kp.isVisible) continue;
        include(kp.x, kp.y);
      }
    }

    // Fallback 3: alle Keypoints unabhängig von Confidence.
    if (included < 2) {
      for (final kp in frame.keypoints.values) {
        include(kp.x, kp.y);
      }
    }

    if (minX == null || minY == null || maxX == null || maxY == null) {
      return const Rect.fromLTWH(0.0, 0.0, 1.0, 1.0);
    }

    final width = (maxX! - minX!).abs();
    final height = (maxY! - minY!).abs();
    const minSize = 0.001;

    if (width < minSize || height < minSize) {
      final cx = (minX! + maxX!) / 2;
      final cy = (minY! + maxY!) / 2;
      final halfW = math.max(width / 2, minSize / 2);
      final halfH = math.max(height / 2, minSize / 2);
      return Rect.fromLTRB(
        (cx - halfW).clamp(0.0, 1.0),
        (cy - halfH).clamp(0.0, 1.0),
        (cx + halfW).clamp(0.0, 1.0),
        (cy + halfH).clamp(0.0, 1.0),
      );
    }

    return Rect.fromLTRB(minX!, minY!, maxX!, maxY!);
  }

  pose.PoseFrame _scalePoseToMatch(
    pose.PoseFrame source,
    pose.PoseFrame target,
  ) {
    final src = _poseBounds(source);
    final tgt = _poseBounds(target);

    final safeSrcWidth = math.max(src.width, 0.001);
    final safeSrcHeight = math.max(src.height, 0.001);

    final scaleX = (tgt.width / safeSrcWidth).clamp(_minScale, _maxScale);
    final scaleY = (tgt.height / safeSrcHeight).clamp(_minScale, _maxScale);

    final srcCx = src.left + src.width / 2;
    final srcCy = src.top + src.height / 2;
    final tgtCx = tgt.left + tgt.width / 2;
    final tgtCy = tgt.top + tgt.height / 2;

    final scaled = <String, pose.Keypoint>{};
    for (final entry in source.keypoints.entries) {
      final kp = entry.value;
      final x = ((kp.x - srcCx) * scaleX + tgtCx).clamp(0.0, 1.0);
      final y = ((kp.y - srcCy) * scaleY + tgtCy).clamp(0.0, 1.0);

      scaled[entry.key] = pose.Keypoint(
        label: kp.label,
        x: x,
        y: y,
        confidence: kp.confidence,
      );
    }

    return pose.PoseFrame(
      timestamp: source.timestamp,
      frameIndex: source.frameIndex,
      keypoints: scaled,
      qualityScore: source.qualityScore,
    );
  }

  pose.PoseFrame _normalizePose(pose.PoseFrame frame) {
    final shL = _kp(frame, 'left_shoulder');
    final shR = _kp(frame, 'right_shoulder');
    final hipL = _kp(frame, 'left_hip');
    final hipR = _kp(frame, 'right_hip');

    if (shL == null || shR == null || hipL == null || hipR == null) {
      return frame;
    }

    final shoulderMid = Offset((shL.dx + shR.dx) / 2, (shL.dy + shR.dy) / 2);
    final hipMid = Offset((hipL.dx + hipR.dx) / 2, (hipL.dy + hipR.dy) / 2);

    final angle = math.atan2(shR.dy - shL.dy, shR.dx - shL.dx);
    final cosA = math.cos(-angle);
    final sinA = math.sin(-angle);

    final torso = (shoulderMid - hipMid).distance;
    final safeTorso = math.max(torso, 0.001);

    final normalized = <String, pose.Keypoint>{};
    for (final entry in frame.keypoints.entries) {
      final kp = entry.value;

      final dx = kp.x - hipMid.dx;
      final dy = kp.y - hipMid.dy;

      final rx = dx * cosA - dy * sinA;
      final ry = dx * sinA + dy * cosA;

      final nx = rx / safeTorso;
      final ny = ry / safeTorso;

      normalized[entry.key] = pose.Keypoint(
        label: kp.label,
        x: nx,
        y: ny,
        confidence: kp.confidence,
      );
    }

    return pose.PoseFrame(
      timestamp: frame.timestamp,
      frameIndex: frame.frameIndex,
      keypoints: normalized,
      qualityScore: frame.qualityScore,
    );
  }

  void _openMovenetDataScreen() {
    final userPosition = _effectiveUserPositions()[_selectedPosition];
    final proPosition = _selectedProSwing?.positions[_selectedPosition];
    if (userPosition == null || proPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MoveNet Daten für diese Position fehlen')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComparisonMovenetDataScreen(
          positionName: _formatPositionName(_selectedPosition),
          proName: _selectedProSwing!.golferName,
          userKeypoints: userPosition.keypoints,
          proKeypoints: proPosition.keypoints,
        ),
      ),
    );
  }

  String _formatPositionName(String name) {
    return name
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}

class _UserMarkerPainter extends CustomPainter {
  final pose.PoseFrame userPose;
  final pose.PoseFrame proPose;
  final bool showSpineMarker;
  final bool showHipOverAnkleMarker;
  final bool showShoulderOverHandMarker;
  final bool showKneeFlexMarker;

  _UserMarkerPainter({
    required this.userPose,
    required this.proPose,
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

    Offset? kp(String label, pose.PoseFrame f) {
      final k = f.getKeypoint(label);
      if (k == null || !k.isVisible) return null;
      return Offset(k.x * size.width, k.y * size.height);
    }

    if (showSpineMarker) {
      final hipL = kp('left_hip', userPose);
      final hipR = kp('right_hip', userPose);
      final shL = kp('left_shoulder', proPose);
      final shR = kp('right_shoulder', proPose);
      final hipLPro = kp('left_hip', proPose);
      final hipRPro = kp('right_hip', proPose);

      if (hipL != null &&
          hipR != null &&
          shL != null &&
          shR != null &&
          hipLPro != null &&
          hipRPro != null) {
        final hipMid = Offset((hipL.dx + hipR.dx) / 2, (hipL.dy + hipR.dy) / 2);

        final proHipMid =
            Offset((hipLPro.dx + hipRPro.dx) / 2, (hipLPro.dy + hipRPro.dy) / 2);
        final proShoulderMid =
            Offset((shL.dx + shR.dx) / 2, (shL.dy + shR.dy) / 2);

        final dx = proHipMid.dx - proShoulderMid.dx;
        final dy = proHipMid.dy - proShoulderMid.dy;
        final angle = math.atan2(dx, dy);

        final length = size.height * 0.6;
        final end = Offset(
          hipMid.dx + length * math.sin(angle),
          hipMid.dy - length * math.cos(angle),
        );
        canvas.drawLine(hipMid, end, paint);
      }
    }

    if (showHipOverAnkleMarker) {
      final hip = kp('right_hip', userPose);
      final ankle = kp('right_ankle', userPose);
      if (hip != null && ankle != null) {
        final end = Offset(hip.dx, ankle.dy);
        canvas.drawLine(hip, end, paint);
      }
    }

    if (showShoulderOverHandMarker) {
      final shoulder = kp('right_shoulder', userPose);
      final wrist = kp('right_wrist', userPose);
      if (shoulder != null && wrist != null) {
        final end = Offset(shoulder.dx, wrist.dy);
        canvas.drawLine(shoulder, end, paint);
      }
    }

    if (showKneeFlexMarker) {
      final hip = kp('right_hip', userPose);
      final knee = kp('right_knee', userPose);
      final ankle = kp('right_ankle', userPose);
      if (hip != null && knee != null && ankle != null) {
        canvas.drawLine(hip, knee, paint);
        canvas.drawLine(knee, ankle, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _UserMarkerPainter oldDelegate) => true;
}

