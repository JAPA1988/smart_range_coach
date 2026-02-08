import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/user_swing.dart';
import 'swing_comparison_screen.dart';

class SwingReviewScreen extends StatefulWidget {
  final UserSwing userSwing;

  const SwingReviewScreen({super.key, required this.userSwing});

  @override
  State<SwingReviewScreen> createState() => _SwingReviewScreenState();
}

class _SwingReviewScreenState extends State<SwingReviewScreen> {
  late VideoPlayerController _videoController;
  bool _isVideoInitialized = false;
  int _currentFrame = 0;
  Map<String, UserKeyPosition> _markedPositions = {};

  final List<String> _keyPositionNames = [
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
    _initializeVideo();
    if (widget.userSwing.markedPositions != null) {
      _markedPositions = Map.from(widget.userSwing.markedPositions!);
    }
  }

  Future<void> _initializeVideo() async {
    _videoController =
        VideoPlayerController.file(File(widget.userSwing.videoPath));
    await _videoController.initialize();

    _videoController.addListener(() {
      final position = _videoController.value.position.inMilliseconds;
      final frameIndex = _frameIndexFromTimestamp(position);

      if (frameIndex != _currentFrame) {
        setState(() => _currentFrame = frameIndex);
      }
    });

    if (!mounted) return;
    setState(() => _isVideoInitialized = true);
  }

  int _frameIndexFromTimestamp(int positionMs) {
    if (widget.userSwing.frames.isEmpty) return 0;
    int closestIndex = 0;
    int closestDiff = (widget.userSwing.frames.first.timestampMs - positionMs)
        .abs();

    for (int i = 1; i < widget.userSwing.frames.length; i++) {
      final diff =
          (widget.userSwing.frames[i].timestampMs - positionMs).abs();
      if (diff < closestDiff) {
        closestDiff = diff;
        closestIndex = i;
      }
    }

    return closestIndex;
  }

  void _markCurrentPosition(String positionName) {
    if (_markedPositions.containsKey(positionName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$positionName already marked!')),
      );
      return;
    }

    if (widget.userSwing.frames.isEmpty) return;
    if (_currentFrame >= widget.userSwing.frames.length) return;

    final frameData = widget.userSwing.frames[_currentFrame];

    setState(() {
      _markedPositions[positionName] = UserKeyPosition(
        frameIndex: _currentFrame,
        timestampMs: frameData.timestampMs,
        keypoints: frameData.keypoints,
        markedAt: DateTime.now(),
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Marked ${_formatPositionName(positionName)} at frame $_currentFrame',
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _previousFrame() {
    if (widget.userSwing.frames.isEmpty) return;
    if (_currentFrame > 0) {
      final targetMs = widget.userSwing.frames[_currentFrame - 1].timestampMs;
      _videoController.seekTo(Duration(milliseconds: targetMs));
    }
  }

  void _nextFrame() {
    if (widget.userSwing.frames.isEmpty) return;
    if (_currentFrame < widget.userSwing.frames.length - 1) {
      final targetMs = widget.userSwing.frames[_currentFrame + 1].timestampMs;
      _videoController.seekTo(Duration(milliseconds: targetMs));
    }
  }

  void _goToComparison() {
    if (_markedPositions.length < _keyPositionNames.length) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Incomplete Marking'),
          content: const Text(
            'Please mark all 7 key positions before comparing.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SwingComparisonScreen(
          userSwing: widget.userSwing.copyWith(
            markedPositions: _markedPositions,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVideoInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mark Key Positions'),
        actions: [
          TextButton.icon(
            onPressed: _markedPositions.length == _keyPositionNames.length
                ? _goToComparison
                : null,
            icon: const Icon(Icons.compare_arrows, color: Colors.white),
            label: const Text('Compare', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: _videoController.value.aspectRatio,
            child: VideoPlayer(_videoController),
          ),
          if (widget.userSwing.frames.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No pose frames available. Please analyze the video first.',
              ),
            )
          else ...[
            _buildVideoControls(),
            Expanded(child: _buildKeyPositionsList()),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[200],
      child: Column(
        children: [
          Slider(
            value: _currentFrame.toDouble(),
            min: 0,
            max: (widget.userSwing.frames.length - 1).toDouble(),
            onChanged: (value) {
              final frameIndex = value.toInt();
              final targetMs =
                  widget.userSwing.frames[frameIndex].timestampMs;
              _videoController.seekTo(Duration(milliseconds: targetMs));
            },
          ),
          Text(
            'Frame: $_currentFrame / ${widget.userSwing.frames.length - 1}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _previousFrame,
                icon: const Icon(Icons.skip_previous),
                iconSize: 32,
              ),
              const SizedBox(width: 16),
              IconButton(
                onPressed: () {
                  setState(() {
                    if (_videoController.value.isPlaying) {
                      _videoController.pause();
                    } else {
                      _videoController.play();
                    }
                  });
                },
                icon: Icon(
                  _videoController.value.isPlaying
                      ? Icons.pause_circle
                      : Icons.play_circle,
                ),
                iconSize: 48,
              ),
              const SizedBox(width: 16),
              IconButton(
                onPressed: _nextFrame,
                icon: const Icon(Icons.skip_next),
                iconSize: 32,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeyPositionsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _keyPositionNames.length,
      itemBuilder: (context, index) {
        final positionName = _keyPositionNames[index];
        final isMarked = _markedPositions.containsKey(positionName);
        final markedFrame =
            isMarked ? _markedPositions[positionName]!.frameIndex : null;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: isMarked ? Colors.green[50] : null,
          child: ListTile(
            leading: Checkbox(
              value: isMarked,
              onChanged: null,
              activeColor: Colors.green,
            ),
            title: Text(
              _formatPositionName(positionName),
              style: TextStyle(
                fontWeight: isMarked ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: isMarked
                ? Text('Frame: $markedFrame',
                    style: const TextStyle(color: Colors.green))
                : null,
            trailing: ElevatedButton(
              onPressed: isMarked
                  ? null
                  : () => _markCurrentPosition(positionName),
              style: ElevatedButton.styleFrom(
                backgroundColor: isMarked ? Colors.grey : Colors.blue,
              ),
              child: Text(isMarked ? 'Marked' : 'Mark Now'),
            ),
          ),
        );
      },
    );
  }

  String _formatPositionName(String name) {
    return name
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }
}
