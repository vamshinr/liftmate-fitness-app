# Revamp LiftMate: Swift to Flutter + Firebase Transition

We are revamping the LiftMate app from a Swift project to a Flutter + Firebase application. This plan covers environment setup, code cleanup, Firebase integration, application architecture, and UI/logic implementation.

## User Review Required

> [!WARNING]
> This process will completely delete the existing Swift project files (`LiftMate.xcodeproj`, `Coach`, `CoachTests`, `ML`, `project.yml`). If you have any local commits or uncommitted Swift code you want to keep, please back them up before approving this plan.

> [!IMPORTANT]
> To configure Firebase automatically via FlutterFire, we will need:
> 1. You to be logged into the Firebase CLI (`firebase login`).
> 2. Active internet access to create/configure a Firebase project.
> 3. CocoaPods installed on your Mac for iOS dependency management.

## Open Questions

> [!IMPORTANT]
> 1. **Firebase Project Name:** Do you want us to create a new Firebase project (e.g., `liftmate-fitness-app`), or connect to an existing Firebase project? If existing, please provide the Firebase Project ID.
> 2. **Claude API Integration:** The original roadmap mentions a "Bring-your-own Claude API key" setting. Should we build this directly into the local state, or store it in Firestore per user?
> 3. **Machine Wayfinding & Pose Estimation:** For the MVP, should we use Google ML Kit on-device Pose Detection / Object Detection, or provide a high-fidelity simulated/interactive view for validation? (Google ML Kit is compatible with Flutter on iOS).

## Proposed Changes

### [Cleanup Phase]

Remove all Swift-specific files and folders from the workspace directory to clean the workspace before initializing Flutter.

#### [DELETE] [LiftMate.xcodeproj](file:///Users/vamshinagireddy/Downloads/Fitness-app/LiftMate.xcodeproj)
#### [DELETE] [Coach](file:///Users/vamshinagireddy/Downloads/Fitness-app/Coach)
#### [DELETE] [CoachTests](file:///Users/vamshinagireddy/Downloads/Fitness-app/CoachTests)
#### [DELETE] [ML](file:///Users/vamshinagireddy/Downloads/Fitness-app/ML)
#### [DELETE] [project.yml](file:///Users/vamshinagireddy/Downloads/Fitness-app/project.yml)

---

### [Environment Setup Phase]

Install the required tools:
1. **Homebrew Packages**:
   - `brew install --cask flutter` (Flutter SDK)
   - `brew install cocoapods` (CocoaPods for iOS build dependencies)
2. **Firebase CLI**:
   - `npm install -g firebase-tools` (Firebase CLI)
   - `dart pub global activate flutterfire_cli` (FlutterFire CLI for Firebase-Flutter configuration)

---

### [Flutter Project Phase]

Initialize the Flutter project in the current directory and add dependencies.

#### [NEW] [pubspec.yaml](file:///Users/vamshinagireddy/Downloads/Fitness-app/pubspec.yaml)
Initialize the project structure:
```bash
flutter create --org com.liftmate --project-name liftmate --platforms ios .
```

Add dependencies:
- `firebase_core`: Core Firebase SDK
- `firebase_auth`: Authentication
- `cloud_firestore`: Firestore database
- `camera`: For pose detection overlay & wayfinding
- `google_mlkit_pose_detection`: Real-time pose estimation
- `flutter_tts`: Voice cues for rep counter
- `provider` or `flutter_riverpod`: State management
- `google_fonts`: Modern typography (Inter, Outfit)
- `shared_preferences`: Storing Claude API key locally

---

### [Application Implementation Phase]

We will build a clean, premium, dark-mode Flutter application structure:

#### [NEW] [lib/main.dart](file:///Users/vamshinagireddy/Downloads/Fitness-app/lib/main.dart)
App entry point, initializes Firebase, configures the dark theme, and routes to onboarding or the main navigation hub.

#### [NEW] [lib/screens/navigation_hub.dart](file:///Users/vamshinagireddy/Downloads/Fitness-app/lib/screens/navigation_hub.dart)
Main tab navigation structure:
- **Workout/Coach** (Form analysis & rep counting)
- **Wayfinding** (Camera machine scanner & tutorials)
- **Nutrition** (Daily plain-English calorie/protein helper)
- **History** (Logged workouts list from Firestore)
- **Settings** (Claude API key, profile, account details)

#### [NEW] [lib/screens/workout/workout_screen.dart](file:///Users/vamshinagireddy/Downloads/Fitness-app/lib/screens/workout/workout_screen.dart)
- Selection of lifts: Squat, Deadlift, Bench Press.
- Camera preview screen with a skeleton layout.
- Rep counter HUD with interactive simulation + real-time posture indicators.
- A "Human Review Escalation" button that uploads the video/data to Firebase for human coaching review.

#### [NEW] [lib/screens/wayfinding/wayfinding_screen.dart](file:///Users/vamshinagireddy/Downloads/Fitness-app/lib/screens/wayfinding/wayfinding_screen.dart)
- Camera scanner view targeting machines.
- Overlay matching detected machines.
- Bottom sheet popup showing 30s tutorial and today's workout details.

#### [NEW] [lib/screens/nutrition/nutrition_screen.dart](file:///Users/vamshinagireddy/Downloads/Fitness-app/lib/screens/nutrition/nutrition_screen.dart)
- Simple modern dashboard showing protein target, calorie limit.
- Recommendation card suggesting 3 cheap, high-protein meals based on preferences.

#### [NEW] [lib/screens/settings/settings_screen.dart](file:///Users/vamshinagireddy/Downloads/Fitness-app/lib/screens/settings/settings_screen.dart)
- Profile details and BYO Claude API Key configuration.
- Firebase integration and setup status.

---

## Verification Plan

### Automated Tests
- Run `flutter doctor` to ensure Flutter, Android toolchain, and Xcode command line tools are fully green.
- Run `flutter analyze` to check Dart code quality.

### Manual Verification
- Launch the iOS simulator: `open -a Simulator`.
- Build and run the app: `flutter run`.
- Verify transition and responsiveness of each tab.
- Test firebase initialization locally.
