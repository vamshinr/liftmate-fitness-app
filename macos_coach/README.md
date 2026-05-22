# LiftMate Coach (macOS)

A native SwiftUI Mac app that watches you lift through the camera and gives **real-time form feedback** with **3D pose detection**.

Inspired by the "AI squat coach" demo — same architecture (on-device pose + rules + TTS), but using Apple's `VNDetectHumanBodyPose3DRequest` so the rules engine works in real 3D meters/degrees instead of 2D pixel ratios.

## Architecture

```
AVCaptureSession (built-in camera or Continuity Camera)
        │ CMSampleBuffer @ ~30 fps
        ▼
VNDetectHumanBodyPoseRequest      (2D — for skeleton overlay)
VNDetectHumanBodyPose3DRequest    (3D — runs on Neural Engine + GPU)
        │
        ▼
BiomechEngine  ─►  phase FSM (Standing / Descending / At Bottom / Ascending)
                ├─ live cues based on 3D measurements
                │     • depth = hipY − kneeY (meters)
                │     • forward lean = torso angle from vertical (degrees)
                │     • knee valgus = knee deviation from hip→ankle line (degrees)
                ├─ rep counter on phase return-to-standing
                └─ per-rep scoring (deductions on bad reps, recovery on clean)
        │
        ▼
CoachViewModel
        │
        ├─►  SwiftUI overlay
        │       ├─ HUD bar:   LIFT | Reps N | Score 100 | 22 fps | Voice ON
        │       ├─ Skeleton:  white bones with halo + cyan joints
        │       ├─ Centered:  "Step into frame", "Stand side-on, full body"
        │       ├─ Cue chip:  current correction with color severity
        │       └─ Score bar: vertical gauge on the right edge
        │
        └─►  VoiceCoach (AVSpeechSynthesizer, throttled to 2.5 s, deduped)
```

## What this is not

This is **not** an LLM-driven app. There's zero network traffic — `network.client` is denied in the entitlements. Detection is sub-50 ms per frame on Apple Silicon (Neural Engine + GPU). Cost per session: $0.

## Build

The Xcode project is generated from `project.yml` with [xcodegen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen   # one time
cd macos_coach
xcodegen generate       # regenerate project after editing project.yml
open LiftMateCoach.xcodeproj
# Press ⌘R to run, or:
xcodebuild -project LiftMateCoach.xcodeproj -scheme LiftMateCoach build
```

Requires:
- macOS 14+ (`VNDetectHumanBodyPose3DRequest`)
- Xcode 15+ (Swift 5.10)
- A camera

On first launch, macOS will prompt for camera permission. Grant it. Subsequent launches don't prompt.

## File map

```
Sources/LiftMateCoach/
├── LiftMateCoachApp.swift        – @main SwiftUI App
├── ContentView.swift             – top-level view, owns CoachViewModel
├── Camera/CameraService.swift    – AVFoundation capture session
├── Pose/PoseEngine.swift         – Vision 2D + 3D requests, debouncing
├── Pose/BiomechRules.swift       – phase FSM, 3D rules, scoring
├── Coach/CoachViewModel.swift    – glue layer, observable state
├── Coach/VoiceCoach.swift        – throttled AVSpeechSynthesizer
└── UI/
    ├── CameraPreview.swift       – AVCaptureVideoPreviewLayer NSViewRep
    ├── SkeletonOverlay.swift     – Canvas-based bones + joints
    ├── HUDBar.swift              – monospace top bar
    ├── CenteredOverlay.swift     – framing + cue chip + status + controls
    └── ScoreBar.swift            – right-edge vertical gauge

Resources/
├── Info.plist                    – NSCameraUsageDescription etc.
├── LiftMateCoach.entitlements    – app-sandbox + camera
└── Assets.xcassets/              – AppIcon
```

## What it currently does

- **Squat** is fully tuned: phase tracking, depth check in real cm, knee valgus check in degrees, forward lean check, rep counting + scoring.
- **Deadlift / OHP** show up in the lift cycle but reuse the squat rules for now — extend `BiomechEngine.evaluate` for proper hinge / press-specific rules.
- **Voice** uses macOS's Alex voice (or system fallback). Toggle in HUD.
- **Camera switching** works if you have multiple cameras (built-in + Continuity Camera, USB webcam, etc.).

## Roadmap

- [ ] Per-lift rule sets (deadlift hinge, OHP layback, bench bar path)
- [ ] Bar path tracking via secondary object detection model
- [ ] Side-by-side replay of the last set with frame-by-frame skeleton
- [ ] Per-fault learned classifier (small CNN on pose sequences)
- [ ] Export set summary as JSON for sync to the LiftMate iOS app
