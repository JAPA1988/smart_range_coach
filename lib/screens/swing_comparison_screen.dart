import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/user_swing.dart' as user;

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
  String? _selectedPosition;
  final Map<String, KeyPositionEntry> _entries = {};

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  String _swingIdFromVideoPath(String videoPath) {
    return videoPath.split(Platform.pathSeparator).last.replaceAll('.mp4', '');
  }

  Future<void> _loadEntries() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final outDir = Directory(
        '${dir.path}${Platform.pathSeparator}smart_range_coach${Platform.pathSeparator}key_positions',
      );
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
        _selectedPosition = _positionOrder.firstWhere(
          (pos) => _entries.containsKey(pos),
          orElse: () => '',
        );
        if (_selectedPosition!.isEmpty) {
          _selectedPosition = _entries.keys.first;
        }
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected =
        _selectedPosition != null ? _entries[_selectedPosition] : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Swing Review')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(child: Text('Keine Key Positions gefunden.'))
              : Column(
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
                            onChanged: (value) {
                              setState(() {
                                _selectedPosition = value;
                              });
                            },
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              const Text('Raster'),
                              Switch(
                                value: _showRaster,
                                onChanged: (value) {
                                  setState(() => _showRaster = value);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (selected != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'Frame: ${selected.frameIndex} • '
                          'Zeit: ${selected.timestampMs}ms • '
                          'Quality: ${(selected.qualityScore * 100).toStringAsFixed(0)}%',
                        ),
                      ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: selected == null
                            ? const Center(child: Text('Keine Auswahl'))
                            : Image.file(
                                File(
                                  _showRaster
                                      ? selected.rasterPath
                                      : selected.imagePath,
                                ),
                                fit: BoxFit.contain,
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

