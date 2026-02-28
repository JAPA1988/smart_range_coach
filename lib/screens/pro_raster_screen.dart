import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/pose_frame.dart' as pose;
import '../models/reference_swing.dart' as ref;
import '../services/reference_swing_service.dart';
import '../widgets/pro_projection_raster_view.dart';

class ProRasterScreen extends StatefulWidget {
  const ProRasterScreen({super.key});

  @override
  State<ProRasterScreen> createState() => _ProRasterScreenState();
}

class _ProRasterScreenState extends State<ProRasterScreen> {
  static const double _sideCropCm = 0.0;
  static const double _projectionShiftX = 0.0;
  static const double _projectionShiftCm = 0.0;

  final _service = ReferenceSwingService();
  ref.ReferenceSwing? _swing;
  String? _selectedPosition;
  bool _loading = true;
  String? _error;
  bool _showSpineAngleMarker = false;

  @override
  void initState() {
    super.initState();
    _loadFirstPro();
  }

  Future<void> _loadFirstPro() async {
    try {
      final swings = await _service.loadSwingMinimal('swing_1_andy_7iron');
      if (!mounted) return;

      setState(() {
        _swing = swings;
        _selectedPosition = swings.keyPositions.isNotEmpty
            ? swings.keyPositions.first
            : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load pro swing: $e';
        _loading = false;
      });
    }
  }

  pose.PoseFrame _toPoseFrame(ref.KeyPosition pos) {
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

  Offset? _kpForMetrics(pose.PoseFrame frame, String label) {
    final kp = frame.getKeypoint(label);
    if (kp == null || kp.confidence < 0.1) return null;
    return Offset(kp.x, kp.y);
  }

  double? _spineAngle(pose.PoseFrame frame) {
    final hipL = _kpForMetrics(frame, 'left_hip');
    final hipR = _kpForMetrics(frame, 'right_hip');
    final shL = _kpForMetrics(frame, 'left_shoulder');
    final shR = _kpForMetrics(frame, 'right_shoulder');
    if (hipL == null || hipR == null || shL == null || shR == null) return null;

    final hipMid = Offset((hipL.dx + hipR.dx) / 2, (hipL.dy + hipR.dy) / 2);
    final shMid = Offset((shL.dx + shR.dx) / 2, (shL.dy + shR.dy) / 2);

    final dy = hipMid.dy - shMid.dy;
    final dx = hipMid.dx - shMid.dx;
    if (dy == 0 && dx == 0) return null;

    return (math.atan2(dx, dy).abs()) * 180 / math.pi;
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
        appBar: AppBar(title: const Text('Pro Raster')),
        body: Center(child: Text(_error!)),
      );
    }

    if (_swing == null || _selectedPosition == null) {
      return const Scaffold(
        body: Center(child: Text('No data')),
      );
    }

    final pos = _swing!.positions[_selectedPosition];
    if (pos == null) {
      return const Scaffold(
        body: Center(child: Text('Position not available')),
      );
    }

    final poseFrame = _toPoseFrame(pos);
    final videoInfo = _swing!.videoInfo;
    debugPrint('ProRaster video: ${videoInfo.width} x ${videoInfo.height}');
    final spineAngle = _spineAngle(poseFrame);

    return Scaffold(
      appBar: AppBar(
        title: Text('Pro Raster • ${_swing!.golferName}'),
      ),
      body: Column(
        children: [
          _buildPositionSelector(),
          _buildMarkerPanel(spineAngle),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: videoInfo.width / videoInfo.height,
                child: ProProjectionRasterView(
                  poseFrame: poseFrame,
                  sideCropCm: _sideCropCm,
                  rightHalfOnly: false,
                  projectionShiftX: _projectionShiftX,
                  projectionShiftCm: _projectionShiftCm,
                  showGrid: true,
                  showSpineAngleMarker: _showSpineAngleMarker,
                  minConfidence: 0.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPositionSelector() {
    final positions = _swing!.keyPositions;
    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: positions.length,
        itemBuilder: (context, index) {
          final position = positions[index];
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

  Widget _buildMarkerPanel(double? spineAngle) {
    final angleText = spineAngle == null
        ? '—'
        : '${spineAngle.toStringAsFixed(1)}°';

    return Container(
      color: Colors.black.withOpacity(0.05),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Switch(
            value: _showSpineAngleMarker,
            onChanged: (value) {
              setState(() => _showSpineAngleMarker = value);
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Spine Angle Marker ($angleText)'),
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
