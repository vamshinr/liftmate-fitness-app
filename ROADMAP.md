# Roadmap

Each phase ends with something you'd actually demo or validate with users.

## Stage 1 — Validation (Months 0–2, Target 50 paying users)
Goal: Validate the core AI form check and machine wayfinding features on a small cohort from Reddit and TikTok.

- [ ] Xcode project with iOS target, SwiftUI app shell
- [ ] Tab nav: Workout / Wayfinding / History / Settings 
- [ ] `PoseEngine` running `VNDetectHumanBodyPoseRequest`
- [ ] Skeleton overlay drawn on top of camera preview
- [ ] Implement AI Form Check for 3 core lifts: Squat, Deadlift, Bench Press
- [ ] Rep counter HUD & Voice cues via `AVSpeechSynthesizer` (terse mode)
- [ ] In-Gym Machine Wayfinding: simple object detection to recognize 3 basic gym machines and play a 30s tutorial
- [ ] Hardcoded week 1 beginner plan
- [ ] Nutrition Guidance: Hardcoded "eat X calories, here are 3 cheap meals" decision engine

**Go-to-market action:** Post weekly in r/beginnerfitness, r/xxfitness, and r/fitness form-check megathreads offering free AI form analysis. Build a TikTok account showing the machine-wayfinding demo ("I pointed my phone at a gym machine — here’s what the AI said").

## Stage 2 — Reach $1k MRR (Months 2–5)
Goal: Expand features, launch marketplace, and prepare for broader launch.

- [ ] Add remaining beginner lifts to AI Form Check (Row, Lunge, Lat Pulldown, Leg Press, Pull-up, OHP)
- [ ] `ClaudeClient` with prompt-caching, streaming, tool use for personalized weekly planning
- [ ] Human Marketplace stub: Recruit 5-10 independent coaches. Build one-tap escalation UI to send session video/data for $5-10 human review.
- [ ] SwiftData persistence + HealthKit `HKWorkoutSession` write
- [ ] Payment integration (StoreKit 2) for Plus tier ($14.99/mo) and Marketplace sessions.
- [ ] Onboarding (goals, equipment, injury notes, BYO Claude API key)

**Go-to-market action:** Write SEO content for beginner-pain Google queries ("how to use cable machine," "gym intimidation"). Launch on Product Hunt once 200+ paying subs and a polished 90-second demo video are ready.

## Stage 3 — Reach $10k MRR (Months 5–12)
Goal: Scale acquisition and add intermediate features to retain users.

- [ ] Pro/Plateau Tier ($24.99/mo) with "Plateau Breaker" mode
- [ ] Full food logging via Vision + Claude vision
- [ ] Adaptive day-level plan generator (reads last 14 days + HealthKit recovery)
- [ ] Conversational chat tab with workout-aware context
- [ ] Voice chat with `SFSpeechRecognizer` input

**Go-to-market action:** App Store Optimization for "AI personal trainer," "gym beginner." Affiliate program with mid-tier fitness YouTubers (10k-100k subs). Market Pro tier in r/weightroom and r/gainit.

## Backlog (post-1.0)
- Barbell tracking via on-device object detection
- Apple Watch companion app
- macOS Catalyst standalone app
- Live Activities / Dynamic Island support

## Benchmarks & Pivot Triggers
- If AI form-check accuracy <80% on user-uploaded video in pilot: Pivot to make the human marketplace the headline.
- If trial-to-paid <3% after 2,000 trials: Double down on the in-gym camera teach-me feature instead of nutrition.
- If beginner CAC via organic Reddit > $15: Rotate to TikTok demo content exclusively.
- If marketplace fills <50% of bookings: Drop it from v1 and run AI-only at $9.99/mo until 2,000 subs.
