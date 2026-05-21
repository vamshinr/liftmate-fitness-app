# LiftMate — AI Personal Trainer

> An AI personal trainer with a human safety net, designed for gym beginners. v1: real-time form analysis, machine wayfinding, and voice coaching.

See [`PRODUCT.md`](PRODUCT.md), [`ARCHITECTURE.md`](ARCHITECTURE.md), [`ROADMAP.md`](ROADMAP.md) for the long story.

## Status

**Phase 0 — Scaffold.** Working iOS app:
- Camera capture (1080p30, front-facing)
- On-device 19-joint pose detection via `VNDetectHumanBodyPoseRequest`
- 1€ Filter smoothing per joint
- Real-time skeleton overlay on the camera preview
- `SquatAnalyzer` state machine (standing → descending → bottom → ascending) with rep counting, depth quality, torso-lean and knee-valgus warnings
- Voice cues via `AVSpeechSynthesizer`
- Tab nav with stub screens for Coach chat / History / Settings
- Unit tests for the analyzer + joint math

## Setup (one-time)

You need **Xcode 15+** and an **iPhone** (the camera + Vision pipeline don't meaningfully work in the Simulator).

```bash
# 1. Make sure xcode-select points at Xcode.app (not Command Line Tools).
#    Currently on this Mac it points at /Library/Developer/CommandLineTools, so this is required.
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version   # verify — should print "Xcode 15.x" or similar

# 2. Install XcodeGen (one-time)
brew install xcodegen

# 3. Generate the Xcode project from project.yml
cd /Users/vamshinagireddy/Downloads/Fitness-app
xcodegen generate

# 4. Open Xcode
open LiftMate.xcodeproj
```

In Xcode:

1. Select the **LiftMate** target → **Signing & Capabilities**.
2. Set your **Team** (your personal Apple ID is fine for sideloading).
3. Change the **Bundle Identifier** if `com.liftmate.app` is taken (`com.<yourname>.liftmate`).
4. Plug in an iPhone, select it as the run destination, hit ⌘R.
5. First launch will prompt for **Camera permission** → allow.

## How to test the squat analyzer

1. Open the app, **Workout** tab.
2. Tap **Bodyweight Squat** (the only tile enabled in Phase 0).
3. Prop your phone landscape, ~2–3 m away, roughly at hip-to-knee height. Step into frame.
4. The skeleton should appear over you. The HUD shows **Reps**, **Last** (rep quality), **Tempo**.
5. Do 10 squats. You should hear "Good", "Excellent", or corrective cues like "Go lower" / "Chest up" / "Knees out".

If the skeleton flickers or joints don't appear, reposition the camera so your whole body is in frame and there's reasonable light.

## Manual fallback (if you don't want XcodeGen)

1. In Xcode: **File → New → Project → iOS → App** → name **Coach**, interface **SwiftUI**, language **Swift**.
2. Delete the placeholder `ContentView.swift` and `CoachApp.swift` Xcode creates.
3. Drag the `Coach/` folder from this repo into the project navigator (check "Copy items if needed" off, "Create groups", add to **Coach** target).
4. Open the target's **Info** tab and add the keys from `project.yml`'s `info.properties` block (`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`, `NSSpeechRecognitionUsageDescription`).
5. Add `UIBackgroundModes` = `audio` so voice cues survive screen-off.
6. Build and run.

## Running tests

```bash
xcodebuild test -project Coach.xcodeproj -scheme Coach -destination 'platform=iOS Simulator,name=iPhone 15'
```

Or hit ⌘U in Xcode. Tests don't need a camera — `SquatAnalyzerTests` feeds synthetic pose frames through the analyzer.

## What's intentionally broken / TODO in Phase 0

- Only **squat** is wired up; the other 9 exercise tiles are visible but disabled.
- The Coach, History, and Settings tabs are stubs (Settings has a working API-key field for later phases).
- No persistence yet — workouts are not saved to SwiftData or HealthKit.
- No Apple Watch companion.
- Skeleton overlay uses screen-space coordinates that assume preview aspect-fill — there can be slight misalignment when the camera AR differs from the screen AR. Will be fixed once we add `AVCaptureVideoPreviewLayer.layerPointConverted(fromCaptureDevicePoint:)` translation.

## Project layout

```
Fitness-app/
├── project.yml                 # XcodeGen spec
├── PRODUCT.md ARCHITECTURE.md ROADMAP.md
├── README.md
├── Coach/
│   ├── App/                    # @main + root tabs
│   ├── Features/
│   │   ├── Workout/            # camera view, skeleton overlay, library
│   │   ├── Coach/              # chat (stub)
│   │   ├── History/            # stub
│   │   └── Settings/
│   ├── Domain/
│   │   ├── Pose/               # PoseEngine, OneEuroFilter, JointMath, PoseFrame
│   │   ├── Analyzers/          # ExerciseAnalyzer protocol + SquatAnalyzer
│   │   └── Workout/            # Exercise enum
│   ├── Infrastructure/
│   │   ├── Camera/             # AVCaptureSession wrapper
│   │   └── Voice/              # AVSpeechSynthesizer wrapper
│   └── Resources/              # Info.plist, Assets.xcassets
└── CoachTests/
    ├── SquatAnalyzerTests.swift
    └── JointMathTests.swift
```

## Next phase

See [`ROADMAP.md`](ROADMAP.md). Stage 1 (Months 0-2) will focus on validating the core value prop with 50 paying users, adding the Deadlift and Bench Press analyzers, implementing the in-gym machine wayfinding feature, and getting early feedback from Reddit and TikTok.
