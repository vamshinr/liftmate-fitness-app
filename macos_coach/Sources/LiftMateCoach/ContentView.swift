import SwiftUI

struct ContentView: View {
    @StateObject private var coach = CoachViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Camera preview fills the frame; pose overlay drawn on top.
            CameraPreview(session: coach.session)
                .ignoresSafeArea()

            SkeletonOverlay(
                landmarks: coach.skeletonLandmarks2D,
                imageSize: coach.imageSize,
                mirror: coach.isMirrored
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Right-edge vertical score gauge.
            HStack {
                Spacer()
                ScoreBar(score: coach.score)
                    .frame(width: 16)
                    .padding(.trailing, 14)
            }
            .padding(.top, 100)
            .padding(.bottom, 160)

            // HUD top + cues bottom.
            VStack(spacing: 0) {
                HUDBar(
                    lift: coach.lift,
                    phase: coach.phase.label,
                    reps: coach.reps,
                    score: coach.score,
                    fps: coach.fps,
                    voiceOn: coach.voiceOn,
                    onToggleVoice: { coach.toggleVoice() }
                )
                .padding(.horizontal, 14)
                .padding(.top, 14)

                Spacer()

                if !coach.framingMessage.isEmpty {
                    CenteredOverlay(text: coach.framingMessage)
                        .padding(.bottom, 24)
                } else if !coach.liveCue.isEmpty {
                    CueChip(text: coach.liveCue, color: coach.liveCueColor)
                        .padding(.bottom, 6)
                }

                StatusFooter(text: coach.statusMessage)
                    .padding(.bottom, 12)

                Controls(
                    voiceOn: coach.voiceOn,
                    canFlip: coach.availableCameraCount > 1,
                    isRunning: coach.isRunning,
                    onFlip: { coach.flipCamera() },
                    onPickLift: { coach.cycleLift() },
                    onResetSet: { coach.resetSet() }
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
        }
        .task {
            await coach.start()
        }
        .onDisappear {
            coach.stop()
        }
    }
}

#Preview {
    ContentView()
}
