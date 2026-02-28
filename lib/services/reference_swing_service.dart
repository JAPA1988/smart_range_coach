import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/reference_swing.dart';

class ReferenceSwingService {
  static const List<String> _swingIds = [
    'swing_1_andy_7iron',
  ];

  Future<List<ReferenceSwing>> loadAllSwings() async {
    final swings = <ReferenceSwing>[];

    for (final swingId in _swingIds) {
      final swing = await loadSwing(swingId);
      swings.add(swing);
    }

    return swings;
  }

  Future<ReferenceSwing> loadSwing(String swingId) async {
    final basePath = 'assets/reference_swings/$swingId';

    final metadataJson = await _loadJson('$basePath/metadata.json');
    final keyPositionsJson = await _loadJson('$basePath/key_positions.json');
    final analysisJson = await _loadJson('$basePath/position_analysis.json');

    return ReferenceSwing.fromJson(
      metadataJson,
      keyPositionsJson,
      analysisJson,
    );
  }

  Future<ReferenceSwing> loadSwingMinimal(String swingId) async {
    final basePath = 'assets/reference_swings/$swingId';

    final metadataJson = await _loadJson('$basePath/metadata.json');
    final keyPositionsJson = await _loadJson('$basePath/key_positions.json');

    return ReferenceSwing.fromJson(
      metadataJson,
      keyPositionsJson,
      const {},
    );
  }

  Future<Map<String, dynamic>> _loadJson(String path) async {
    final jsonString = await rootBundle.loadString(path);
    return json.decode(jsonString) as Map<String, dynamic>;
  }
}
