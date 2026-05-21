# Architecture

## Stack at a glance

```
┌──────────────────────────────────────────────────────────────────┐
│                          SwiftUI App                              │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐ │
│  │   Camera   │  │  Wayfinder │  │   Coach    │  │  History   │ │
│  │   + Form   │  │ (Machines) │  │   (Chat)   │  │  + Charts  │ │
│  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘ │
└────────┼───────────────┼────────────────┼────────────────┼───────┘
         │               │                │                │
         ▼               ▼                ▼                ▼
┌──────────────────────────────────────────────────────────────────┐
│                        Domain Layer (Swift)                       │
│  PoseEngine  •  ExerciseAnalyzer  •  CoachBrain  •  WorkoutLog   │
└─────┬─────────────────┬───────────────────┬───────────────────────┘
      │                 │                   │
      ▼                 ▼                   ▼
┌─────────────┐  ┌─────────────┐  ┌─────────────────────────────┐
│   Vision    │  │  SwiftData  │  │   AI & Backend Layer        │
│  AVFound.   │  │  HealthKit  │  │  ┌───────────────────────┐  │
│  Speech     │  │             │  │  │ FoundationModels (on) │  │
│             │  │             │  │  │  → cues, wayfinding   │  │
│             │  │             │  │  └───────────────────────┘  │
│             │  │             │  │  ┌───────────────────────┐  │
│             │  │             │  │  │  Claude API (cloud)   │  │
│             │  │             │  │  │  → planning, nutri    │  │
│             │  │             │  │  └───────────────────────┘  │
│             │  │             │  │  ┌───────────────────────┐  │
│             │  │             │  │  │  Human Marketplace    │  │
│             │  │             │  │  │  → review escalation  │  │
│             │  │             │  │  └───────────────────────┘  │
└─────────────┘  └─────────────┘  └─────────────────────────────┘
```

## Module breakdown

### `PoseEngine` & `MachineDetector`
- **PoseEngine**: Wraps `VNDetectHumanBodyPoseRequest` (2D, all devices) and `VNDetectHumanBodyPose3DRequest` (3D, iPhone 12 Pro+).
- iOS 18+: prefer new Swift `DetectHumanBodyPoseRequest` with `detectsHands = true` (holistic body + hands in one pass — needed for grip cues).
- 2D runs every captured frame (~5–10 ms on A16+). 3D runs at **1–2 Hz on a separate serial queue** (~30–50 ms per call, too slow for 30fps) — used opportunistically for depth-disambiguation (e.g., squat depth).
- **MachineDetector**: Uses CoreML + Vision object detection (`VNCoreMLRequest`) to identify gym machines (e.g. cable machine, leg press) for the Wayfinding feature.
- Capture at **1080p30 not 4K** (no accuracy gain, ~4× thermal cost). Set `alwaysDiscardsLateVideoFrames = true`.
- Input: `CMSampleBuffer` from `AVCaptureVideoDataOutput`.
- Output: stream of `PoseFrame { joints: [Joint: Point + confidence], timestamp, source: 2D|3D }` or `MachineObservation`.
- Runs on a `dispatch_queue_t` separate from the camera queue. Drops frames if downstream is busy.
- Confidence floor (0.3 default) — joints below floor marked `unreliable`, not dropped, so smoothing can still run.
- Smoothing: **1€ Filter** per joint (preserves fast motion better than EMA, low-jitter on slow motion).

### AI device gating

| Device cohort (2026) | LLM path |
|---|---|
| Apple Intelligence eligible (iPhone 15 Pro+, iPhone 16+, M-series iPad/Mac) on iOS/macOS 26+ | Foundation Models on-device for routine/structured (~30 tok/s); Claude API for deep reasoning |
| Everything else (iOS 17/18, non-AI-eligible hardware) | Claude Haiku as the "fast" path, Claude Sonnet/Opus as the "deep" path |

Both paths emit the same `CoachReply` shape — UI is unaware of which model produced it.

### `ExerciseAnalyzer` (protocol)
```swift
protocol ExerciseAnalyzer {
    var exercise: Exercise { get }
    mutating func ingest(_ frame: PoseFrame) -> AnalyzerEvent?
}

enum AnalyzerEvent {
    case repCompleted(quality: RepQuality, tempo: Tempo, notes: [FormNote])
    case formWarning(FormNote)         // mid-rep correction
    case setupBad(reason: String)      // user not in frame, side angle wrong
}
```

Each exercise = one concrete analyzer implementing a **state machine** over key joint angles:

- `SquatAnalyzer`: knee angle + hip angle + torso angle. States: `standing → descending → bottom → ascending → standing`. Rep counts at return to `standing`. Quality: depth (knee < 100° = parallel), torso lean angle, knee valgus (compare left/right hip-knee-ankle line).
- `PushUpAnalyzer`: elbow angle + body-line angle (shoulder-hip-ankle). States: `top → descending → bottom → ascending → top`. Quality: depth (elbow < 90°), body-line straight (170°–185°), neck position.
- ...etc for 10 exercises in v1.

All analyzers consume the same `PoseFrame` stream. Active analyzer is chosen by current workout context.

### `CoachBrain` & Marketplace Router
- Single entry point for AI: `func ask(_ context: CoachContext) async throws -> CoachReply`.
- Routes based on latency need + privacy + cost + context:
  - **Foundation Models** (on-device, iOS 26+): single-set summaries, voice cue rewording, machine wayfinding tutorials.
  - **Claude API** (Sonnet/Opus): programming, nutrition guidance, conversational coaching, "redesign my week" requests.
  - **Marketplace Escrow**: If user taps "Get Human Review" ($5-$10), the session video and `WorkoutLog` are packaged and securely transmitted to a human coach dashboard backend.
- Both AI paths go through a `CoachPrompt` builder that injects:
  - User profile (goals, injury notes, equipment)
  - Last 14 days of workout summaries (compressed)
  - HealthKit recovery signals (HRV trend, sleep last night, resting HR)
  - Current session events
- Prompt caching on the Claude path: system prompt + user profile + 14-day history cached for 5 minutes (huge cost win during a session).

### `WorkoutLog`
- SwiftData models: `Workout`, `Set`, `RepLog`, `FormNote`, `SessionSummary`.
- Mirrored to HealthKit via `HKWorkoutSession` (iOS 26 brought this to iPhone — we use it directly, no Watch dependency).

### UI layer (SwiftUI)
- `CameraWorkoutView`: `AVCaptureVideoPreviewLayer` + `MTKView` overlay for skeleton + HUD for rep count, form cues.
- `WorkoutLibraryView`: grid of exercises, tap to start a freestyle set or pick today's plan.
- `CoachChatView`: full-screen chat. Streamed responses. Voice input via `SFSpeechRecognizer`.
- `HistoryView`: charts via Swift Charts.

## Voice coaching

- `AVSpeechSynthesizer` with `AVAudioSession.Category.playback` mixed with workout music.
- Cue priority queue — only one cue at a time. New higher-priority cue interrupts current.
- Cue voice: `com.apple.voice.premium.en-US.Zoe` or user-selected. AirPods spatial audio when available.
- Three verbosity modes: `silent | terse (default) | conversational`.

## Data flow during a live set (the hot path)

```
camera (30fps) → AVCaptureVideoDataOutputSampleBufferDelegate
              → CVPixelBuffer
              → PoseEngine (Vision request) ── 25-30ms ──┐
                                                          ▼
                                          PoseFrame stream (AsyncStream)
                                                          │
                          ┌───────────────────────────────┼─────────────────────────────┐
                          ▼                               ▼                             ▼
              SkeletonRenderer (Metal)          ExerciseAnalyzer.ingest      Background recorder
              (overlay on preview)              (state machine, 5-15µs)      (writes frames if user opts in)
                                                          │
                                                          ▼
                                              AnalyzerEvent
                                                          │
                                                          ├─► Voice cue (AVSpeechSynthesizer)
                                                          ├─► HUD update (rep count, tempo)
                                                          └─► WorkoutLog write
```

End of set → `CoachBrain.ask(.setSummary(events))` → on-device LLM produces a one-line summary ("Solid set. 8 reps, 2 partial. Tempo getting fast on the way down — slow the eccentric next set."), spoken aloud.

End of workout → `CoachBrain.ask(.sessionReview(workout))` → Claude API gives a deeper review and adjusts tomorrow's plan.

## Privacy

- **No video leaves the device.** Ever. Pose extraction is local; only derived events (rep count, form notes) are persisted.
- Claude API receives text only: exercise name, joint-angle summaries ("avg knee depth 95°"), counts, durations. No frames, no images.
- HealthKit access scoped to what we actually need; clear in-app explanation.
- Bring-your-own API key model in v1 means user's data goes only to their own Anthropic account.

## Project layout (Xcode)

```
Coach/
├── Coach.xcodeproj
├── Coach/
│   ├── App/
│   │   ├── CoachApp.swift
│   │   └── ContentView.swift
│   ├── Features/
│   │   ├── Workout/
│   │   │   ├── CameraWorkoutView.swift
│   │   │   ├── WorkoutLibraryView.swift
│   │   │   └── SetSummaryView.swift
│   │   ├── History/
│   │   ├── Coach/        // chat
│   │   └── Settings/
│   ├── Domain/
│   │   ├── Pose/
│   │   │   ├── PoseEngine.swift
│   │   │   ├── PoseFrame.swift
│   │   │   └── JointMath.swift
│   │   ├── Analyzers/
│   │   │   ├── ExerciseAnalyzer.swift
│   │   │   ├── SquatAnalyzer.swift
│   │   │   ├── PushUpAnalyzer.swift
│   │   │   └── ...
│   │   ├── Coach/
│   │   │   ├── CoachBrain.swift
│   │   │   ├── ClaudeClient.swift
│   │   │   └── FoundationModelsClient.swift
│   │   └── Workout/
│   │       ├── Exercise.swift
│   │       ├── Workout.swift
│   │       └── WorkoutLog.swift
│   ├── Infrastructure/
│   │   ├── Camera/CameraSession.swift
│   │   ├── Voice/Speaker.swift
│   │   ├── HealthKit/HealthKitBridge.swift
│   │   └── Persistence/SwiftDataStack.swift
│   └── Resources/
│       └── Exercises.json       // exercise definitions, form rules
├── CoachTests/
│   └── AnalyzerTests/           // critical — replay recorded pose streams against expected rep counts
└── README.md
```

## Testing strategy

- **Analyzer tests** are the most important code we'll write. We record JSON pose-frame fixtures of real reps (good form, bad form, edge cases) and replay them through analyzers asserting expected events. No camera needed in CI.
- UI snapshot tests for camera HUD states.
- Manual on-device validation matrix per exercise (this can't be fully automated).
