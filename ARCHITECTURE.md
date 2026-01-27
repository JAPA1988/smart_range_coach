# Pre-computed Shoulder Tracking - Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          RECORDING PHASE                                 │
└─────────────────────────────────────────────────────────────────────────┘

User Records Video
       │
       ▼
┌──────────────────┐
│ _stopRecording() │──► Save video file: video_123456.mp4
└──────────────────┘
       │
       ▼
┌─────────────────────────────────┐
│ _analyzeVideoAndSaveShoulders() │
└─────────────────────────────────┘
       │
       ├─► Show progress dialog: "Analysiere Video..."
       │
       ├─► Initialize VideoPlayerController
       │
       ├─► Loop through video (every 100ms):
       │   ├─► Seek to timestamp
       │   ├─► Generate shoulder positions (simulated)
       │   │   • Left shoulder: (x, y) normalized 0..1
       │   │   • Right shoulder: (x, y) normalized 0..1
       │   └─► Add to shoulderData array
       │
       ├─► Save JSON file: video_123456_shoulders.json
       │   {
       │     "timestamp_ms": 0,
       │     "left": {"x": 0.35, "y": 0.30},
       │     "right": {"x": 0.65, "y": 0.30}
       │   }
       │
       └─► Close progress dialog

═══════════════════════════════════════════════════════════════════════════

┌─────────────────────────────────────────────────────────────────────────┐
│                          PLAYBACK PHASE                                  │
└─────────────────────────────────────────────────────────────────────────┘

User Opens Video
       │
       ▼
┌──────────────┐
│  initState() │
└──────────────┘
       │
       ├─► Initialize VideoPlayerController
       │
       └─► _loadPrecomputedShoulders()
           ├─► Check for video_123456_shoulders.json
           ├─► Load and parse JSON
           └─► Store in _precomputedShoulders

Video Playing
       │
       ▼
┌──────────────────┐          ┌────────────────────────────────┐
│  _ctrlListener() │──────────┤ _updateShoulderMarkersFrom     │
│  (every frame)   │          │        Precomputed()           │
└──────────────────┘          └────────────────────────────────┘
                                       │
                                       ├─► Get current video position (ms)
                                       │
                                       ├─► Optimized frame lookup:
                                       │   ├─► Check nearby frames first
                                       │   │   (±20 from last index)
                                       │   └─► Fallback to full search
                                       │
                                       ├─► Find closest frame (within 150ms)
                                       │
                                       ├─► Convert normalized coords → pixels
                                       │   • leftX_px = leftX * videoWidth
                                       │   • leftY_px = leftY * videoHeight
                                       │
                                       └─► Update UI markers
                                           setState(() {
                                             _leftShoulderMarker = (x, y)
                                             _rightShoulderMarker = (x, y)
                                           })

═══════════════════════════════════════════════════════════════════════════

┌─────────────────────────────────────────────────────────────────────────┐
│                       FALLBACK MECHANISM                                 │
└─────────────────────────────────────────────────────────────────────────┘

No JSON File Found?
       │
       ▼
┌──────────────────────────────┐
│ _ensureShoulderTimerRunning()│──► Check: _precomputedShoulders == null?
└──────────────────────────────┘
       │
       └─► YES: Start Timer (1000ms interval)
           └─► _trackShouldersOnce()
               ├─► Capture current frame
               ├─► Run MoveNet inference (if available)
               ├─► Or use heuristic detection
               └─► Update shoulder markers

═══════════════════════════════════════════════════════════════════════════

┌─────────────────────────────────────────────────────────────────────────┐
│                       PERFORMANCE COMPARISON                             │
└─────────────────────────────────────────────────────────────────────────┘

BEFORE (Timer-based):
┌─────────────┐  Every 1000ms   ┌──────────────┐
│  Playing    │────────────────▶│  Run MoveNet │──► CPU/GPU intensive
│  Video      │                 │  Inference   │    Battery drain
└─────────────┘                 └──────────────┘    Jumping markers

AFTER (Pre-computed):
┌─────────────┐  Every frame    ┌──────────────┐
│  Playing    │────────────────▶│  Array       │──► O(1) lookup
│  Video      │  ~16-60ms       │  Lookup      │    Minimal CPU
└─────────────┘                 └──────────────┘    Smooth markers

═══════════════════════════════════════════════════════════════════════════

┌─────────────────────────────────────────────────────────────────────────┐
│                       DATA FLOW DIAGRAM                                  │
└─────────────────────────────────────────────────────────────────────────┘

Recording
    ↓
[video_123456.mp4] ──► Analysis ──► [video_123456_shoulders.json]
                                            │
                                            │
                                            ▼
                                     ┌──────────────┐
                                     │  JSON Array  │
                                     │  600 entries │
                                     │  ~30KB file  │
                                     └──────────────┘
                                            │
                                            │
                                            ▼
                                      Playback
                                            │
                                            ▼
                                   ┌─────────────────┐
                                   │ Smooth Markers  │
                                   │ on Video        │
                                   └─────────────────┘

═══════════════════════════════════════════════════════════════════════════

┌─────────────────────────────────────────────────────────────────────────┐
│                       FILE STRUCTURE                                     │
└─────────────────────────────────────────────────────────────────────────┘

Documents/
└── smart_range_coach/
    ├── video_1706374800000.mp4          (recorded video)
    ├── video_1706374800000_shoulders.json   (shoulder data)
    ├── video_1706375400000.mp4
    └── video_1706375400000_shoulders.json

JSON Format:
[
  {
    "timestamp_ms": 0,        // Video position in milliseconds
    "left": {
      "x": 0.35,              // Normalized 0..1 (left edge = 0, right edge = 1)
      "y": 0.30               // Normalized 0..1 (top = 0, bottom = 1)
    },
    "right": {
      "x": 0.65,
      "y": 0.30
    }
  },
  {
    "timestamp_ms": 100,
    "left": {"x": 0.36, "y": 0.29},
    "right": {"x": 0.64, "y": 0.31}
  },
  // ... one entry every 100ms
]

═══════════════════════════════════════════════════════════════════════════

┌─────────────────────────────────────────────────────────────────────────┐
│                       OPTIMIZATION DETAILS                               │
└─────────────────────────────────────────────────────────────────────────┘

Sequential Playback (typical):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Frame lookup: O(1)
Current index: 45
Search range: [25..65] (±20 frames)
Typical iterations: 1-3
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

After User Seeks:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Frame lookup: O(n) fallback
Search all 600 frames
Find new index, cache for next lookup
Next lookups: back to O(1)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Memory Usage:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1-minute video at 100ms intervals:
• 600 frames
• ~50 bytes per frame
• ~30KB total
• Negligible memory impact
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Key Takeaways

1. **One-Time Analysis**: Shoulder positions computed once after recording
2. **Smooth Playback**: Frame-by-frame updates from pre-computed data
3. **Efficient Lookup**: O(1) for sequential playback, O(n) fallback for seeking
4. **Graceful Fallback**: Timer-based tracking if JSON not available
5. **Ready for MoveNet**: Infrastructure in place for real pose detection

## Implementation Highlights

- ✅ **Separation of Concerns**: Analysis and playback are independent
- ✅ **Performance**: Minimal CPU during playback
- ✅ **Reliability**: Proper resource cleanup with finally blocks
- ✅ **Maintainability**: Clear code structure and documentation
- ✅ **Future-Proof**: Easy to integrate real MoveNet inference
