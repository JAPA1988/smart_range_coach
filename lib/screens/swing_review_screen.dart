  String _formatPositionName(String name) {
    if (name == 'address') return 'Address';
    if (name == 'takeaway') return 'Takeaway';
    if (name == 'set_position') return 'Set Position';
    if (name == 'top_position') return 'Top Position';
    if (name == 'downswing') return 'Downswing';
    if (name == 'impact') return 'Impact';
    if (name == 'follow_through') return 'Follow Through';
    return name;
  }

  void _markCurrentPosition(String positionName) {
    // TODO: Implement marking logic
  }

  void _previousFrame() {
    // TODO: Implement previous frame logic
  }

  void _nextFrame() {
    // TODO: Implement next frame logic
  }
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/user_swing.dart';
import '../services/skeleton_image_service.dart';
import 'swing_comparison_screen.dart';

class SwingReviewScreen extends StatefulWidget {
  final UserSwing userSwing;

  const SwingReviewScreen({super.key, required this.userSwing});

  @override
  State<SwingReviewScreen> createState() => _SwingReviewScreenState();
}

class _SwingReviewScreenState extends State<SwingReviewScreen> {
  bool _isGeneratingImage = false;
  late VideoPlayerController _videoController;
  int _currentFrame = 0;
  Map<String, dynamic> _markedPositions = {};
  List<String> _keyPositionNames = [
    'address',
    'takeaway',
    'set_position',
    'top_position',
    'downswing',
    'impact',
    'follow_through',
  ];
  // ...existing code...
                '${_markedPositions.length}/7',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          IconButton(
            onPressed:
                _markedPositions.length == 7 ? _goToComparison : null,
            icon: const Icon(Icons.compare_arrows),
            tooltip: 'Compare with Pro',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 6,
                  child: _buildKeyPositionsList(),
                ),
                // ...existing code...
              ],
            ),
          ),
        ],
      ),
                          final positionName = _keyPositionNames[index];
                          final isMarked = _markedPositions.containsKey(positionName);
                          final markedFrame = isMarked ? _markedPositions[positionName]!.frameIndex : null;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: isMarked ? Colors.green[50] : Colors.white,
                            elevation: isMarked ? 2 : 1,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        isMarked ? Icons.check_circle : Icons.radio_button_unchecked,
                                        color: isMarked ? Colors.green : Colors.grey,
                                        size: 20,
                                      ),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _formatPositionName(positionName),
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: isMarked ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (isMarked) ...[
                                    SizedBox(height: 4),
                                    Text(
                                      'Frame: $markedFrame',
                                      style: TextStyle(fontSize: 11, color: Colors.green[700]),
                                    ),
                                  ],
                                  if (!isMarked && !_videoController.value.isPlaying) ...[
                                    SizedBox(height: 8),
                                    SizedBox(
                                        Widget _buildKeyPositionsList() {
                                          return Container(
                                            color: Colors.grey[100],
                                            child: ListView.builder(
                                              padding: EdgeInsets.all(8),
                                              itemCount: _keyPositionNames.length,
                                              itemBuilder: (context, index) {
                                                final positionName = _keyPositionNames[index];
                                                final isMarked = _markedPositions.containsKey(positionName);
                                                final markedFrame = isMarked ? _markedPositions[positionName]['frameIndex'] : null;
                                                return Card(
                                                  margin: EdgeInsets.only(bottom: 8),
                                                  color: isMarked ? Colors.green[50] : Colors.white,
                                                  elevation: isMarked ? 2 : 1,
                                                  child: Padding(
                                                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: <Widget>[
                                                        Row(
                                                          children: <Widget>[
                                                            Icon(
                                                              isMarked ? Icons.check_circle : Icons.radio_button_unchecked,
                                                              color: isMarked ? Colors.green : Colors.grey,
                                                              size: 20,
                                                            ),
                                                            SizedBox(width: 8),
                                                            Expanded(
                                                              child: Text(
                                                                _formatPositionName(positionName),
                                                                style: TextStyle(
                                                                  fontSize: 14,
                                                                  fontWeight: isMarked ? FontWeight.bold : FontWeight.normal,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        if (isMarked)
                                                          ...[
                                                            SizedBox(height: 4),
                                                            Text(
                                                              'Frame: $markedFrame',
                                                              style: TextStyle(fontSize: 11, color: Colors.green[700]),
                                                            ),
                                                          ],
                                                        if (!isMarked && !_videoController.value.isPlaying)
                                                          ...[
                                                            SizedBox(height: 8),
                                                            SizedBox(
                                                              width: double.infinity,
                                                              child: ElevatedButton(
                                                                onPressed: _isGeneratingImage ? null : () => _markCurrentPosition(positionName),
                                                                style: ElevatedButton.styleFrom(
                                                                  padding: EdgeInsets.symmetric(vertical: 8),
                                                                  backgroundColor: Colors.blue,
                                                                ),
                                                                child: Text(
                                                                  'Mark Now',
                                                                  style: TextStyle(fontSize: 12),
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          );
                                        }
                  _videoController.seekTo(Duration(milliseconds: targetMs));
                  setState(() => _currentFrame = frameIndex);
                }
              },
            ),
          ),
          Text(
            'Frame: $_currentFrame / ${widget.userSwing.frames.length}',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _previousFrame,
                icon: const Icon(Icons.skip_previous),
                iconSize: 32,
                color: Colors.blue[700],
              ),
              const SizedBox(width: 24),
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
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                ),
                iconSize: 56,
                color: Colors.blue[700],
              ),
              const SizedBox(width: 24),
              IconButton(
                onPressed: _nextFrame,
                icon: const Icon(Icons.skip_next),
                iconSize: 32,
                color: Colors.blue[700],
              ),
            ],
          ),
          if (_isGeneratingImage)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Generating skeleton image...',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ...existing code...
    if (name == 'address') return 'Address';
    if (name == 'takeaway') return 'Takeaway';
    if (name == 'set_position') return 'Set Position';
    if (name == 'top_position') return 'Top Position';
    if (name == 'downswing') return 'Downswing';
    if (name == 'impact') return 'Impact';
    if (name == 'follow_through') return 'Follow Through';
    return name;
  }

  Widget _buildVideoControls() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.grey[200],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: _currentFrame.toDouble(),
              min: 0,
              max: (widget.userSwing.frames.length - 1).toDouble(),
              onChangeStart: (_) => _videoController.pause(),
              onChanged: (value) {
                final frameIndex = value.toInt();
                if (frameIndex < widget.userSwing.frames.length) {
                  final targetMs = widget.userSwing.frames[frameIndex].timestampMs;
                  _videoController.seekTo(Duration(milliseconds: targetMs));
                  setState(() => _currentFrame = frameIndex);
                }
              },
            ),
          ),
          Text(
            'Frame: $_currentFrame / ${widget.userSwing.frames.length}',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
          SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _previousFrame,
                icon: Icon(Icons.skip_previous),
                iconSize: 32,
                color: Colors.blue[700],
              ),
              SizedBox(width: 24),
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
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                ),
                iconSize: 56,
                color: Colors.blue[700],
              ),
              SizedBox(width: 24),
              IconButton(
                onPressed: _nextFrame,
                icon: Icon(Icons.skip_next),
                iconSize: 32,
                color: Colors.blue[700],
              ),
            ],
          ),
          if (_isGeneratingImage)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Generating skeleton image...',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildKeyPositionsList() {
    // Duplicate definition removed. Only the correct version above remains.

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }
}
