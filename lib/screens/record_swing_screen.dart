import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/user_swing.dart';
import '../services/video_analysis_service.dart';

class RecordSwingScreen extends StatefulWidget {
  static String? lastAnalyzedVideoPath;

  const RecordSwingScreen({super.key});

  @override
  State<RecordSwingScreen> createState() => _RecordSwingScreenState();
}

class _RecordSwingScreenState extends State<RecordSwingScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isRecording = false;
  bool _isAnalyzing = false;
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
        fps: 120,
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
    if (!mounted) return;
    final videoFile = File(videoPath);
    if (!await videoFile.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Video file not found: $videoPath')),
      );
      return;
    }

    setState(() => _isAnalyzing = true);

    try {
      final analysisService = VideoAnalysisService();
      final userSwing = await analysisService.analyzeVideo(
        videoPath,
        context: context,
        showProgressDialog: false,
        timeout: const Duration(minutes: 2),
      );

      if (!mounted) return;
      RecordSwingScreen.lastAnalyzedVideoPath = userSwing.videoPath;
      // Statt Review-Screen direkt zu öffnen: Ergebnis zurückgeben
      if (kDebugMode) {
        debugPrint('RecordSwingScreen returning UserSwing: ${userSwing.videoPath}');
      }
      Navigator.pop(context, userSwing);
    } on TimeoutException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Analysis timed out: ${e.message ?? ''}')),
      );
      final fallbackSwing = _fallbackSwing(videoPath);
      RecordSwingScreen.lastAnalyzedVideoPath = fallbackSwing.videoPath;

      // Auch im Fehlerfall zurückgeben
      if (kDebugMode) {
        debugPrint('RecordSwingScreen returning fallback UserSwing after timeout: ${fallbackSwing.videoPath}');
      }
      Navigator.pop(context, fallbackSwing);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Analysis failed: $e')),
      );
      final fallbackSwing = _fallbackSwing(videoPath);
      RecordSwingScreen.lastAnalyzedVideoPath = fallbackSwing.videoPath;
      if (kDebugMode) {
        debugPrint('RecordSwingScreen returning fallback UserSwing after error: ${fallbackSwing.videoPath}');
      }
      Navigator.pop(context, fallbackSwing);
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  UserSwing _fallbackSwing(String videoPath) {
    final fileName = videoPath.split(Platform.pathSeparator).last;
    final id = fileName.replaceAll('.mp4', '');
    return UserSwing(
      id: id,
      videoPath: videoPath,
      recordedAt: DateTime.now(),
      frames: const [],
      status: AnalysisStatus.failed,
    );
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
                if (_isAnalyzing)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'ANALYZING... Bitte warten',
                      style: TextStyle(
                        color: Colors.lightBlueAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isAnalyzing
                      ? null
                      : (_isRecording ? _stopRecording : _startRecording),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRecording ? Colors.red : Colors.green,
                    minimumSize: const Size(200, 60),
                  ),
                  child: Text(
                    _isAnalyzing
                        ? 'ANALYZING...'
                        : (_isRecording ? 'STOP' : 'RECORD'),
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
