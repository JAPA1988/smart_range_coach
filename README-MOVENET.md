MoveNet integration (POC)

This repository includes a MoveNet proof-of-concept path in `lib/main.dart`.

Steps to enable MoveNet inference locally:

1) Download a MoveNet model (SinglePose Lightning is a good POC):
   - Example: `movenet_singlepose_lightning.tflite` from TensorFlow model garden or TF Hub.
   - Place the file at `assets/movenet_singlepose_lightning.tflite` in the project root.

2) Install dependencies and fetch packages:

```powershell
flutter pub get
```

3) Run the app on Windows:

```powershell
flutter run -d windows
```

Notes:
- If the asset is missing, the app will gracefully fall back to the existing heuristic detector.
- The POC uses a small nearest-neighbour downsample to feed MoveNet and expects the model to output [1,17,3] keypoints (y,x,score) as MoveNet does.
- For production mobile use, consider model-specific preprocessing (center/crop/scale) and better normalization.
