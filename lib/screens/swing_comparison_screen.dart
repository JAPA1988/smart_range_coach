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

    final proScale = _computeProScaleToUser(userPosition, proPosition);

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
                    child: ClipRect(
                      child: Transform.scale(
                        scale: proScale,
                        alignment: Alignment.center,
                        child: Image.asset(
                          _selectedProSwing!
                              .imagePathForPosition(_selectedPosition),
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

  double _computeProScaleToUser(
    user.UserKeyPosition userPosition,
    ref.KeyPosition proPosition,
  ) {
    final userDistance = _noseToAnkleDistanceUser(userPosition.keypoints);
    final proDistance = _noseToAnkleDistancePro(proPosition.keypoints);

    if (userDistance == null || proDistance == null || proDistance <= 0.0) {
      return 1.0;
    }

    return (userDistance / proDistance).clamp(0.6, 2.4);
  }

  double? _noseToAnkleDistanceUser(Map<String, user.Keypoint> keypoints) {
    final nose = keypoints['nose'];
    final leftAnkle = keypoints['left_ankle'];
    final rightAnkle = keypoints['right_ankle'];
    if (nose == null || leftAnkle == null || rightAnkle == null) {
      return null;
    }

    final ankleMidX = (leftAnkle.x + rightAnkle.x) / 2.0;
    final ankleMidY = (leftAnkle.y + rightAnkle.y) / 2.0;
    return math.sqrt(
      math.pow(ankleMidX - nose.x, 2).toDouble() +
          math.pow(ankleMidY - nose.y, 2).toDouble(),
    );
  }

  double? _noseToAnkleDistancePro(Map<String, ref.Keypoint> keypoints) {
    final nose = keypoints['nose'];
    final leftAnkle = keypoints['left_ankle'];
    final rightAnkle = keypoints['right_ankle'];
    if (nose == null || leftAnkle == null || rightAnkle == null) {
      return null;
    }

    final ankleMidX = (leftAnkle.x + rightAnkle.x) / 2.0;
    final ankleMidY = (leftAnkle.y + rightAnkle.y) / 2.0;
    return math.sqrt(
      math.pow(ankleMidX - nose.x, 2).toDouble() +
          math.pow(ankleMidY - nose.y, 2).toDouble(),
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
