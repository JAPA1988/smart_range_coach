import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/video_analysis_service.dart';
import 'swing_review_screen.dart';

class RecordSwingScreen extends StatefulWidget {
  const RecordSwingScreen({super.key});

  @override
  State<RecordSwingScreen> createState() => _RecordSwingScreenState();
}

class _RecordSwingScreenState extends State<RecordSwingScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isRecording = false;
  bool _isInitialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() => _error = 'No cameras available');
        return;
      }

      final camera = _cameras!.first;
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _cameraController = controller;
        _isInitialized = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Camera init failed: $e');
    }
  }

  Future<void> _startRecording() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    await controller.startVideoRecording();
    if (!mounted) return;
    setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    final controller = _cameraController;
    if (controller == null) return;

    final videoFile = await controller.stopVideoRecording();
    if (!mounted) return;

    setState(() => _isRecording = false);

    await _analyzeVideo(videoFile.path);
  }

  Future<void> _analyzeVideo(String videoPath) async {
    try {
      final analysisService = VideoAnalysisService();
      final userSwing = await analysisService.analyzeVideo(
        videoPath,
        context: context,
      );

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SwingReviewScreen(userSwing: userSwing),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Analysis failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Record Swing')),
        body: Center(child: Text(_error!)),
      );
    }

    if (!_isInitialized || _cameraController == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Record Swing')),
      body: Column(
        children: [
          Expanded(
            child: CameraPreview(_cameraController!),
          ),
          Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                if (_isRecording)
                  const Text(
                    'RECORDING',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isRecording ? _stopRecording : _startRecording,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRecording ? Colors.red : Colors.green,
                    minimumSize: const Size(200, 60),
                  ),
                  child: Text(
                    _isRecording ? 'STOP' : 'RECORD',
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }
}
