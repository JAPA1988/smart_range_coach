import 'dart:io';

import 'package:flutter/material.dart';

import '../models/reference_swing.dart' as ref;
import '../models/user_swing.dart' as user;
import '../services/reference_swing_service.dart';

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
          Expanded(child: _buildSideBySideComparison()),
          _buildMetricsTable(),
        ],
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
    final userPosition = widget.userSwing.markedPositions?[_selectedPosition];
    final proPosition = _selectedProSwing!.positions[_selectedPosition];

    if (userPosition == null || proPosition == null) {
      return const Center(child: Text('Position data not available'));
    }

    return Row(
      children: [
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
                child: userPosition.skeletonImagePath != null
                    ? Image.file(
                        File(userPosition.skeletonImagePath!),
                        fit: BoxFit.contain,
                      )
                    : const Center(child: Text('No image saved')),
              ),
            ],
          ),
        ),
        Container(width: 2, color: Colors.grey[400]),
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
                child: Image.asset(
                  _selectedProSwing!.imagePathForPosition(_selectedPosition),
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricsTable() {
    final userPosition = widget.userSwing.markedPositions?[_selectedPosition];
    final proAnalysis = _selectedProSwing!.analysis[_selectedPosition];

    if (userPosition == null || proAnalysis == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[100],
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
          _buildMetricRow('Shoulder Rotation', null, proAnalysis.shoulderRotation),
          _buildMetricRow('Hip Rotation', null, proAnalysis.hipRotation),
        ],
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
