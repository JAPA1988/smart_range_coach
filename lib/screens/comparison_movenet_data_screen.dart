import 'package:flutter/material.dart';

import '../models/reference_swing.dart' as ref;
import '../models/user_swing.dart' as user;

class ComparisonMovenetDataScreen extends StatelessWidget {
  final String positionName;
  final String proName;
  final Map<String, user.Keypoint> userKeypoints;
  final Map<String, ref.Keypoint> proKeypoints;

  const ComparisonMovenetDataScreen({
    super.key,
    required this.positionName,
    required this.proName,
    required this.userKeypoints,
    required this.proKeypoints,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('MoveNet Daten • $positionName'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildKeypointCardUser(),
          ),
          Expanded(
            child: _buildKeypointCardPro(),
          ),
        ],
      ),
    );
  }

  Widget _buildKeypointCardUser() {
    final entries = userKeypoints.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your Swing',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: entries.map((e) {
                  final kp = e.value;
                  return Text(
                    '${e.key}: x=${kp.x.toStringAsFixed(3)} '
                    'y=${kp.y.toStringAsFixed(3)} '
                    'score=${kp.confidence.toStringAsFixed(3)}',
                    style: const TextStyle(fontSize: 12),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypointCardPro() {
    final entries = proKeypoints.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              proName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: entries.map((e) {
                  final kp = e.value;
                  return Text(
                    '${e.key}: x=${kp.x.toStringAsFixed(3)} '
                    'y=${kp.y.toStringAsFixed(3)} '
                    'score=${kp.confidence.toStringAsFixed(3)}',
                    style: const TextStyle(fontSize: 12),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
