import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import '../services/swing_comparison.dart';

class SwingComparisonScreen extends StatefulWidget {
  final String userVideoPath;
  
  const SwingComparisonScreen({required this.userVideoPath, super.key});
  
  @override
  State<SwingComparisonScreen> createState() => _SwingComparisonScreenState();
}

class _SwingComparisonScreenState extends State<SwingComparisonScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _comparisonResult;
  List<Map<String, dynamic>>? _userFrames;
  List<Map<String, dynamic>>? _proFrames;
  
  @override
  void initState() {
    super.initState();
    _loadAndCompare();
  }
  
  Future<void> _loadAndCompare() async {
    try {
      // Lade User-Daten
      final userJsonPath = widget.userVideoPath.replaceAll('.mp4', '_movenet_pose.json');
      final userFile = File(userJsonPath);
      
      if (!await userFile.exists()) {
        setState(() {
          _error = 'Pose-Daten nicht gefunden. Bitte Video neu analysieren.';
          _loading = false;
        });
        return;
      }
      
      final userJson = jsonDecode(await userFile.readAsString());
      _userFrames = List<Map<String, dynamic>>.from(userJson['frames']);
      
      // Lade Profi-Daten
      final proJson = jsonDecode(
        await rootBundle.loadString('assets/pro_swings/sample_pro.json')
      );
      _proFrames = List<Map<String, dynamic>>.from(proJson['frames']);
      
      // Vergleiche
      final result = SwingComparison.compareSwings(_userFrames!, _proFrames!);
      
      setState(() {
        _comparisonResult = result;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Fehler beim Vergleich: $e';
        _loading = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schwung-Vergleich'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : _buildComparisonView(),
    );
  }
  
  Widget _buildComparisonView() {
    final score = _comparisonResult!['overall_score'];
    final keypointScores = _comparisonResult!['keypoint_scores'] as Map<String, dynamic>;
    final recommendations = _comparisonResult!['recommendations'] as List;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Gesamt-Score
          Card(
            color: _getScoreColor(score),
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    '${score.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Aehnlichkeit zu Profi-Schwung',
                    style: TextStyle(fontSize: 18, color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _getScoreLabel(score),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Empfehlungen
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lightbulb, color: Colors.amber, size: 28),
                      SizedBox(width: 8),
                      Text(
                        'Verbesserungsvorschlaege',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...recommendations.map((rec) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('  ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Expanded(
                          child: Text(
                            rec.toString(),
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Keypoint-Details
          const Text(
            'Detaillierte Analyse',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          
          ...keypointScores.entries.map((entry) {
            final keypoint = entry.key;
            final score = entry.value as double;
            
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _formatKeypointName(keypoint),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          '${score.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _getKeypointColor(score),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: score / 100,
                      backgroundColor: Colors.grey.shade300,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getKeypointColor(score),
                      ),
                      minHeight: 8,
                    ),
                  ],
                ),
              ),
            );
          }),
          
          const SizedBox(height: 24),
          
          // Analyse-Info
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue),
                      SizedBox(width: 8),
                      Text(
                        'Analyse-Details',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('User Frames: ${_userFrames!.length}'),
                  Text('Pro Frames: ${_proFrames!.length}'),
                  Text('Verglichene Keypoints: ${keypointScores.length}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Color _getScoreColor(double score) {
    if (score >= 85) return Colors.green.shade700;
    if (score >= 70) return Colors.orange.shade700;
    return Colors.red.shade700;
  }
  
  String _getScoreLabel(double score) {
    if (score >= 90) return 'Hervorragend!';
    if (score >= 80) return 'Sehr gut!';
    if (score >= 70) return 'Gut';
    if (score >= 60) return 'Verbesserungsfaehig';
    return 'Training erforderlich';
  }
  
  Color _getKeypointColor(double score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }
  
  String _formatKeypointName(String key) {
    return key
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}
