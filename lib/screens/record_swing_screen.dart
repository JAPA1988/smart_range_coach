import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/user_swing.dart';
import '../services/video_analysis_service.dart';

class RecordSwingScreen extends StatefulWidget {
  static String? lastAnalyzedVideoPath;

  const RecordSwingScreen({super.key});

  @override
  State<RecordSwingScreen> createState() => _RecordSwingScreenState();
}

class _RecordSwingScreenState extends State<RecordSwingScreen> {
  static const _channel = MethodChannel('com.smart_range_coach/native_camera');

  bool _isLaunchingCamera = true;
  bool _isAnalyzing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startNativeRecording();
    });
  }

  Future<void> _startNativeRecording() async {
    if (mounted) {
      setState(() {
        _error = null;
        _isLaunchingCamera = true;
      });
    }

    try {
      final String? videoPath =
          await _channel.invokeMethod<String>('startNativeCamera');

      if (!mounted) return;

      if (videoPath == null) {
        setState(() {
          _isLaunchingCamera = false;
          _error = 'Recording canceled.';
        });
        return;
      }

      setState(() => _isLaunchingCamera = false);
      await _analyzeVideo(videoPath);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLaunchingCamera = false;
        _error = 'Could not open native camera: $e';
      });
    }
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
        timeout: const Duration(minutes: 5),
      );

      if (!mounted) return;
      RecordSwingScreen.lastAnalyzedVideoPath = userSwing.videoPath;
      if (kDebugMode) {
        debugPrint(
            'RecordSwingScreen returning UserSwing: ${userSwing.videoPath}');
      }
      Navigator.pop(context, userSwing);
    } on TimeoutException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Analysis timed out: ${e.message ?? ''}')),
      );
      Navigator.pop(context, _fallbackSwing(videoPath));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Analysis failed: $e')),
      );
      Navigator.pop(context, _fallbackSwing(videoPath));
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

    return Scaffold(
      appBar: AppBar(title: const Text('Record Swing')),
      body: Center(
        child: _isLaunchingCamera
            ? const Text('Öffne Kamera...')
            : _isAnalyzing
                ? const Text('ANALYZING... Bitte warten')
                : const Text('Warte auf Aufnahme...'),
      ),
    );
  }
}
