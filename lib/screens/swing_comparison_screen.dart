import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      ..color = Colors.white24
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
      var swings = await service.loadAllSwings();
      if (swings.isEmpty) {
        swings = await _loadFallbackProSwings();
      }
      if (!mounted) return;
      setState(() {
        _proSwings = swings;
        _selectedProSwing = swings.isNotEmpty ? swings.first : null;
        _loading = false;
      });
    } catch (e) {
      try {
        final fallback = await _loadFallbackProSwings();
        if (!mounted) return;
        setState(() {
          _proSwings = fallback;
          _selectedProSwing = fallback.isNotEmpty ? fallback.first : null;
          _error = fallback.isEmpty ? 'Failed to load pro swings: $e' : null;
          _loading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _error = 'Failed to load pro swings: $e';
          _loading = false;
        });
      }
    }
  }

  Future<List<ref.ReferenceSwing>> _loadFallbackProSwings() async {
    final raw = await rootBundle.loadString('assets/pro_swings/sample_pro.json');
    final doc = jsonDecode(raw) as Map<String, dynamic>;
    final frames = (doc['frames'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (frames.isEmpty) {
      return const [];
    }

    final frameCount = frames.length;
    final positions = <String, ref.KeyPosition>{};
    final analysis = <String, ref.PositionAnalysis>{};

    for (int i = 0; i < _positions.length; i++) {
      final position = _positions[i];
      final frameIndex = ((frameCount - 1) * (i / (_positions.length - 1)))
          .round()
          .clamp(0, frameCount - 1);
      final frame = frames[frameIndex];
      final timestampMs = (frame['timestamp_ms'] as num?)?.toInt() ?? 0;
      final rawKeypoints =
          (frame['keypoints'] as Map<String, dynamic>? ?? <String, dynamic>{});

      final keypoints = <String, ref.Keypoint>{};
      for (final entry in rawKeypoints.entries) {
        final value = entry.value;
        if (value is Map<String, dynamic>) {
          keypoints[entry.key] = ref.Keypoint(
            x: (value['x'] as num?)?.toDouble() ?? 0.0,
            y: (value['y'] as num?)?.toDouble() ?? 0.0,
            confidence: (value['score'] as num?)?.toDouble() ?? 0.0,
          );
        }
      }

      positions[position] = ref.KeyPosition(
        frame: frameIndex,
        timestampMs: timestampMs,
        keypoints: keypoints,
      );

      analysis[position] = ref.PositionAnalysis(
        spineAngle: 0.0,
        xFactor: 0.0,
        shoulderRotation: 0.0,
        hipRotation: 0.0,
        leftArmAngle: 0.0,
        rightArmAngle: 0.0,
        leftKneeAngle: 0.0,
        rightKneeAngle: 0.0,
      );
    }

    final fallbackSwing = ref.ReferenceSwing(
      swingId: 'sample_pro',
      golferName: (doc['player'] as String?) ?? 'Sample Pro',
      clubType: (doc['club'] as String?) ?? 'Unknown',
      skillLevel: 'Pro',
      videoInfo: ref.VideoInfo(
        fps: 30,
        width: 1280,
        height: 720,
        totalFrames: frameCount,
        durationSeconds:
            ((frames.last['timestamp_ms'] as num?)?.toDouble() ?? 0.0) / 1000,
      ),
      keyPositions: _positions,
      positions: positions,
      analysis: analysis,
    );

    return [fallbackSwing];
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
          _buildPositionSelector(),
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
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: width,
            height: height,
            child: child,
          ),
        ),
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

    return Row(
      children: [
        // User
        Expanded(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Your Swing',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
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
                                    painter: _ComparisonGridPainter()),
                              ),
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: PoseOverlayPainter(
                                    _userToPoseFrame(userPosition),
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
                    child: Image.asset(
                      _selectedProSwing!.imagePathForPosition(_selectedPosition),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) {
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                  painter: _ComparisonGridPainter()),
                            ),
                            Positioned.fill(
                              child: CustomPaint(
                                painter: PoseOverlayPainter(
                                  _proToPoseFrame(proPosition),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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

  Widget _buildMetricsTable() {
    final userPosition = _effectiveUserPositions()[_selectedPosition];
    final proAnalysis = _selectedProSwing!.analysis[_selectedPosition];

    if (userPosition == null || proAnalysis == null) {
      return const SizedBox.shrink();
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      color: Colors.grey[100],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Metrics Comparison',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildMetricRow('Spine Angle', null, proAnalysis.spineAngle),
            _buildMetricRow('X-Factor', null, proAnalysis.xFactor),
            _buildMetricRow(
                'Shoulder Rotation', null, proAnalysis.shoulderRotation),
            _buildMetricRow('Hip Rotation', null, proAnalysis.hipRotation),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, double? userValue, double proValue) {
    final hasUser = userValue != null;
    final diff = hasUser ? (userValue! - proValue).abs() : null;
    final isGood = diff != null && diff < 10;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label),
          ),
          Expanded(
            flex: 2,
            child: Text(
              hasUser ? '${userValue!.toStringAsFixed(1)}°' : '--',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${proValue.toStringAsFixed(1)}°',
              style: const TextStyle(color: Colors.blue),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Icon(
                  isGood ? Icons.check_circle : Icons.warning,
                  color: isGood ? Colors.green : Colors.orange,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  diff != null ? '${diff.toStringAsFixed(1)}°' : '--',
                  style: TextStyle(
                    color: isGood ? Colors.green : Colors.orange,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
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
