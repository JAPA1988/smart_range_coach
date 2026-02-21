import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

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

class KeyPositionsReviewScreen extends StatefulWidget {
  final String swingId;
  final String directoryPath;

  const KeyPositionsReviewScreen({
    required this.swingId,
    required this.directoryPath,
    super.key,
  });

  @override
  State<KeyPositionsReviewScreen> createState() =>
      _KeyPositionsReviewScreenState();
}

class _KeyPositionsReviewScreenState extends State<KeyPositionsReviewScreen> {
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

  Future<void> _loadEntries() async {
    try {
      final dir = Directory(widget.directoryPath);
      if (!await dir.exists()) {
        setState(() => _loading = false);
        return;
      }

      final files = await dir.list().toList();
      for (final entity in files) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.startsWith('${widget.swingId}_') || !name.endsWith('.json')) {
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
        _selectedPosition = _entries.keys.first;
      }
    } catch (_) {
      // noop
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected =
        _selectedPosition != null ? _entries[_selectedPosition] : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Key Positions')),
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
                            items: _entries.keys.map((pos) {
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
                    if (selected != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'Frame: ${selected.frameIndex} • '
                          'Zeit: ${selected.timestampMs}ms • '
                          'Quality: ${(selected.qualityScore * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Expanded(
                      flex: 3,
                      child: Container(
                        margin: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: selected == null
                            ? const Center(child: Text('Keine Auswahl'))
                            : Image.file(
                                File(_showRaster
                                    ? selected.rasterPath
                                    : selected.imagePath),
                                fit: BoxFit.contain,
                              ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: selected == null
                            ? const SizedBox.shrink()
                            : Card(
                                child: ListView(
                                  padding: const EdgeInsets.all(12),
                                  children: [
                                    const Text(
                                      'MoveNet Daten',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ...(selected.keypoints.entries.toList()
                                          ..sort(
                                              (a, b) => a.key.compareTo(b.key)))
                                        .map((entry) {
                                      final data = Map<String, dynamic>.from(
                                          entry.value as Map);
                                      final x =
                                          (data['x'] as num?)?.toDouble() ??
                                              0.0;
                                      final y =
                                          (data['y'] as num?)?.toDouble() ??
                                              0.0;
                                      final s =
                                          (data['score'] as num?)?.toDouble() ??
                                              0.0;
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4),
                                        child: Text(
                                          '${entry.key}: x=${x.toStringAsFixed(3)} '
                                          'y=${y.toStringAsFixed(3)} '
                                          'score=${s.toStringAsFixed(3)}',
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
