import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/user_swing.dart';

class SwingReviewScreen extends StatefulWidget {
  final UserSwing userSwing;
  const SwingReviewScreen({super.key, required this.userSwing});

  @override
  State<SwingReviewScreen> createState() => _SwingReviewScreenState();
}

class _SwingReviewScreenState extends State<SwingReviewScreen> {
  late final VideoPlayerController _videoController;
  bool _isInitialized = false;
  Object? _initError;

  @override
  void initState() {
    super.initState();
    _videoController =
        VideoPlayerController.file(File(widget.userSwing.videoPath));
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      await _videoController.initialize().timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() => _isInitialized = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _initError = e);
    }
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Swing Review')),
      body: Center(
        child: _initError != null
            ? Text('Failed to load video: $_initError')
            : _isInitialized
                ? AspectRatio(
                    aspectRatio: _videoController.value.aspectRatio,
                    child: VideoPlayer(_videoController),
                  )
                : const CircularProgressIndicator(),
      ),
    );
  }
}
