# smart_range_coach

A Flutter application for golf swing analysis using camera recording and MoveNet pose detection.

## Features

### Pre-computed Shoulder Tracking
The app now supports pre-computed shoulder position tracking for smooth, synchronized playback:

- **After Recording**: When you stop a video recording, the app automatically analyzes the video frame-by-frame
- **JSON Storage**: Shoulder positions are saved to a JSON file alongside the video (e.g., `video_123456_shoulders.json`)
- **Smooth Playback**: During video review, shoulder markers are displayed using pre-computed positions based on the current video timestamp
- **No Live Inference**: Eliminates the overhead of running MoveNet inference during playback, improving performance and battery life

### How It Works

1. **Recording Phase**: Record a golf swing using the camera
2. **Analysis Phase**: After stopping, the app analyzes the video every 100ms and stores shoulder positions
3. **Review Phase**: When playing back the video, shoulder markers are smoothly updated based on pre-computed data
4. **Fallback**: If no pre-computed data exists, the app falls back to timer-based live tracking

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Technical Details

### Files Modified
- `lib/main.dart`:
  - Added `_analyzeVideoAndSaveShoulders()` method to analyze recorded videos
  - Modified `_stopRecording()` to trigger analysis after recording
  - Added `_loadPrecomputedShoulders()` to load saved shoulder positions
  - Added `_updateShoulderMarkersFromPrecomputed()` to update UI based on video timestamp
  - Modified `_ensureShoulderTimerRunning()` to skip timer when pre-computed data exists
  - Updated `_ctrlListener` to use pre-computed positions during playback

### Future Enhancements
The current implementation uses simulated shoulder movement to demonstrate the concept. To integrate real MoveNet inference:

1. Render each video frame to a widget with RepaintBoundary during analysis
2. Capture frame as RGBA bytes using `boundary.toImage()`
3. Run `_runMoveNetOnRgba(rgba, w, h)` on each frame
4. Extract keypoints 5 (left shoulder) and 6 (right shoulder) from the result
5. Store the actual detected positions in the JSON file

This infrastructure is already in place and ready for full MoveNet integration.
