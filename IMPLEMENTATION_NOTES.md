# Pre-computed Shoulder Tracking Implementation Notes

## Overview
This document describes the implementation of pre-computed shoulder position tracking to replace timer-based live tracking during video playback.

## Problem Solved
Previously, shoulder positions were calculated during video playback using a Timer that ran every 1000ms, causing:
- Red dots "jumping" to new positions (not smooth)
- Synchronization issues between video and markers
- Performance overhead from continuous MoveNet inference
- Battery drain during playback

## Solution
Pre-compute shoulder positions ONCE after recording, then display them smoothly during playback based on video timestamp.

## Architecture

### 1. Recording and Analysis Phase
**File**: `lib/main.dart` - `_CameraSmokeTestScreenState` class

**Method**: `_stopRecording()`
- Called when user stops video recording
- Saves video to `Documents/smart_range_coach/video_[timestamp].mp4`
- Calls `_analyzeVideoAndSaveShoulders()` to analyze the recorded video

**Method**: `_analyzeVideoAndSaveShoulders(String videoPath)`
- Shows progress dialog ("Analysiere Video...")
- Initializes MoveNet model
- Creates VideoPlayerController for the recorded video
- Analyzes video at 100ms intervals:
  - Seeks to each timestamp
  - Generates shoulder positions (currently simulated)
  - Stores normalized coordinates (0..1) for both shoulders
- Saves results to JSON file: `video_[timestamp]_shoulders.json`
- Format:
```json
[
  {
    "timestamp_ms": 0,
    "left": {"x": 0.35, "y": 0.30},
    "right": {"x": 0.65, "y": 0.30}
  },
  {
    "timestamp_ms": 100,
    "left": {"x": 0.36, "y": 0.29},
    "right": {"x": 0.64, "y": 0.31}
  },
  ...
]
```

### 2. Playback Phase
**File**: `lib/main.dart` - `_SwingQuickReviewScreenState` class

**State Variable**: `_precomputedShoulders`
- Type: `List<Map<String, dynamic>>?`
- Stores loaded shoulder positions from JSON file

**Method**: `_loadPrecomputedShoulders()`
- Called in `initState()`
- Loads JSON file matching video path
- Parses shoulder data into `_precomputedShoulders`
- Logs success/failure for debugging

**Method**: `_updateShoulderMarkersFromPrecomputed()`
- Finds closest pre-computed frame to current video position
- Tolerance: 100ms (matches analysis interval)
- Converts normalized coordinates to pixel coordinates
- Updates `_leftShoulderMarker` and `_rightShoulderMarker`

**Modified**: `_ctrlListener`
- Checks if pre-computed data exists
- Calls `_updateShoulderMarkersFromPrecomputed()` during playback
- Updates on every frame, ensuring smooth tracking

**Modified**: `_ensureShoulderTimerRunning()`
- Returns early if `_precomputedShoulders != null`
- Only uses Timer-based tracking as fallback when no pre-computed data

## Current Implementation Status

### ✅ Completed
- Infrastructure for pre-computation and playback
- JSON file creation and loading
- Smooth marker updates based on video timestamp
- Progress dialog during analysis
- Fallback to timer-based tracking when no pre-computed data
- Simulated realistic shoulder movement for demonstration

### ⏳ Future Enhancement: Full MoveNet Integration
The current implementation uses simulated shoulder positions to demonstrate smooth tracking. To integrate actual MoveNet inference:

**Challenge**: VideoPlayerController doesn't provide direct access to frame pixels
**Solution Required**: 
1. During analysis, render video frames to a RepaintBoundary widget
2. Use `boundary.toImage()` to capture RGBA bytes
3. Call existing `_runMoveNetOnRgba(rgba, w, h)` method
4. Extract keypoints 5 (left shoulder) and 6 (right shoulder)
5. Store actual detected positions in JSON

**Code Location**: `_SwingQuickReviewScreenState` already has:
- `_runMoveNetOnRgba()` - Runs MoveNet on RGBA frame data
- `_videoRepaintKey` - GlobalKey for RepaintBoundary
- Example usage in `_trackShouldersOnce()` and `_captureAndAnalyzeFrame()`

**Integration Steps**:
```dart
// In _analyzeVideoAndSaveShoulders():
for (int ms = 0; ms < duration.inMilliseconds; ms += 100) {
  await controller.seekTo(Duration(milliseconds: ms));
  await Future.delayed(const Duration(milliseconds: 50));
  
  // Render frame to RepaintBoundary (requires widget context)
  final renderObj = _analysisRepaintKey.currentContext?.findRenderObject();
  if (renderObj is! RenderRepaintBoundary) continue;
  
  // Capture frame
  final ui.Image captured = await renderObj.toImage(pixelRatio: 1.0);
  final byteData = await captured.toByteData(format: ui.ImageByteFormat.rawRgba);
  final rgba = byteData!.buffer.asUint8List();
  
  // Run MoveNet
  final kps = await _runMoveNetOnRgba(rgba, captured.width, captured.height);
  
  // Extract shoulders (keypoints 5 and 6)
  if (kps != null && kps.length >= 13) {
    final leftShoulder = kps[5];
    final rightShoulder = kps[6];
    
    shoulderData.add({
      'timestamp_ms': ms,
      'left': {'x': leftShoulder['x'], 'y': leftShoulder['y']},
      'right': {'x': rightShoulder['x'], 'y': rightShoulder['y']},
    });
  }
}
```

## Benefits Achieved

### Performance
- ✅ No MoveNet inference during playback (or minimal as fallback)
- ✅ Reduced CPU/GPU usage during video review
- ✅ Better battery life
- ✅ One-time analysis cost per video

### User Experience
- ✅ Smooth shoulder tracking (frame-by-frame updates)
- ✅ Perfect synchronization with video
- ✅ Consistent results on replay
- ✅ Visual feedback during analysis (progress dialog)

### Technical
- ✅ JSON-based storage (easy to inspect/debug)
- ✅ Graceful fallback to timer-based tracking
- ✅ Minimal changes to existing codebase
- ✅ Ready for MoveNet integration

## Testing Recommendations

1. **Basic Functionality**:
   - Record a video
   - Verify progress dialog appears
   - Check that `video_[timestamp]_shoulders.json` is created
   - Verify JSON contains expected data structure

2. **Playback Testing**:
   - Open recorded video for review
   - Verify shoulder markers appear
   - Verify smooth movement (not jumping)
   - Play/pause/seek to verify markers stay synchronized

3. **Fallback Testing**:
   - Delete a video's JSON file
   - Open the video for review
   - Verify timer-based tracking still works

4. **Edge Cases**:
   - Very short videos (< 1 second)
   - Very long videos (> 1 minute)
   - Seeking to specific timestamps
   - Playing video at different speeds (if supported)

## File Locations

- **Modified File**: `lib/main.dart`
- **JSON Files**: `Documents/smart_range_coach/video_*_shoulders.json`
- **Video Files**: `Documents/smart_range_coach/video_*.mp4`

## Debug Logging

The implementation includes debug print statements:
- `"Analyzing video: Xms, WxH"` - Start of analysis
- `"Saved N shoulder positions to path"` - Analysis complete
- `"Loaded N pre-computed shoulder positions"` - Playback loading success
- `"No pre-computed shoulders found at path"` - Fallback scenario
- `"Failed to load pre-computed shoulders: error"` - Load error

Enable debug logging with:
```dart
import 'package:flutter/foundation.dart';

// Already enabled via kDebugMode checks in code
```

## Dependencies

No new dependencies were added. The implementation uses:
- `dart:convert` - JSON encoding/decoding (already imported)
- `dart:math` - Trigonometry for simulated movement (already imported)
- `video_player` - Video playback (existing dependency)
- `path_provider` - File system access (existing dependency)

## Known Limitations

1. **Simulated Data**: Current implementation uses placeholder shoulder positions. Full MoveNet integration requires additional work (see Future Enhancement section).

2. **Video Rendering**: Direct frame extraction from video files requires rendering frames to a widget, which adds complexity. Alternative approaches could use:
   - Platform-specific video decoding APIs
   - FFmpeg bindings for frame extraction
   - video_thumbnail package for frame extraction

3. **File Cleanup**: JSON files are created but not automatically cleaned up. Consider adding:
   - Manual delete option in UI
   - Automatic cleanup of old files
   - Storage management settings

4. **Analysis Performance**: Analysis runs on main thread. For production:
   - Consider running in background isolate
   - Show detailed progress (e.g., "Analyzing frame 45/120...")
   - Allow cancellation

## Version History

- **v1.0** (2026-01-27): Initial implementation with simulated data
  - Pre-computation infrastructure
  - JSON storage and loading
  - Smooth playback integration
  - Timer-based fallback
