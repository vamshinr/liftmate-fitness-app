# LiftMate — Product Definition

> An AI personal trainer with a human safety net, designed to get beginners through their first 3 months at the gym without looking stupid or hurting themselves.

## The bet

Existing AI fitness apps split into three camps, and none satisfy beginners who are intimidated by the gym:

| Camp | Examples | Price | Why users leave |
|---|---|---|---|
| Form correction only | Kemtai, Onyx, Vay | $19/mo | No programming, no nutrition, trust issues when AI is wrong |
| Algorithm programming | Fitbod, JEFIT, Strong | $8–16/mo | Designed for experienced lifters; requires 10-15 logged workouts to personalize |
| Human + AI hybrid | Future, Caliber | $40–200/mo | Too expensive for beginners; async feedback feels slow |

The gap: **A highly accessible, Apple-native AI coach that watches your form, teaches you how to use equipment, tells you exactly what to eat, and offers a $5 one-tap escalation to a human coach when you need a real safety net.**

## Positioning

> **LiftMate**: Apple-native, on-device-first AI coach with real-time form analysis and cheap on-demand human reviews.

Three key pillars (the Wedge):

1. **Equipment confidence (In-gym wayfinding):** Point your camera at a machine → get a 30-second teach + today’s program. This is our unique wedge for gym anxiety.
2. **AI form check with a human safety net:** Free AI form analysis on the most common beginner lifts (squat, deadlift, bench, OHP, etc.). One-tap escalation to a $5–$10 marketplace human review if the user wants expert reassurance.
3. **Plain-English nutrition coaching:** Not a tracker. A decision. "Today eat ~2,400 calories, ~160g protein; here are 3 cheap meals." 

## Why Apple-only is a feature, not a bug

| Apple capability | What it unlocks |
|---|---|
| Vision framework (free, on-device) | Real-time 19-joint 2D / 17-joint 3D pose and machine object detection. No cloud bill. |
| Foundation Models (iOS 26+) | Free on-device LLM for routine coaching/cues. Zero marginal cost. |
| HealthKit | Heart rate, HRV, sleep → recovery scoring. No competitor wearables needed. |
| AirPods spatial audio | Coach voice positioned next to your ear, not a podcast in your headphones. |
| Continuity Camera | Use iPhone as Mac webcam → train at home with Mac as the big-screen "mirror." |

## Target Audience & Differentiation

- **Target Persona:** The "Stuck/Anxious Beginner" (highly likely to churn from their gym within 6 months).
- **vs. Future:** ~1/10th the price, synchronous real-time form check instead of async delay, cheap-on-demand coaches vs one expensive assigned coach.
- **vs. Fitbod:** Designed specifically for beginners, not algorithms. In-gym camera coaching.
- **vs. MyFitnessPal:** Nutrition coaching over logging every gram. 

## v1 must-haves (MVP)

- Camera capture (iPhone front/back)
- Real-time pose overlay with confidence-weighted joint angles
- 3 core beginner lifts supported first for validation:
  1. Squat
  2. Deadlift (RDL)
  3. Bench Press
- In-gym machine wayfinding (camera points to machine -> identifies -> shows 30s tutorial)
- Per-rep voice cue (good rep, "go lower", "knees out")
- Plain-English nutrition guidance tab
- Integration of a human marketplace stub (one-tap to send session to a human coach)
- Bring-your-own Claude API key in Settings (we eat model cost in beta)

## Pricing Strategy

| Tier | Price | Includes |
|---|---|---|
| Free | $0 | AI program for week 1, AI form check on 3 bodyweight movements, food logging (no coaching). |
| Plus | $14.99/mo or $89/yr | Full AI coach (workouts, form check all lifts, nutrition coaching), 1 free 10-min human marketplace session/mo. |
| Pro | $24.99/mo or $179/yr | Plus + Plateau Breaker mode for intermediates + 3 marketplace sessions/mo + priority form reviews. |
| Marketplace | $5–$25 per session | Ad-hoc deep dives with human coaches (Platform takes 30%). |

## Risks (and what kills the product)

| Risk | Mitigation |
|---|---|
| AI form-check accuracy <80% | Pivot to "AI coach with cheap human form check" — make the human marketplace the headline. |
| Users won't prop up phone | Bundle a magnetic mount in launch press; TikTok demo shows easy setups. |
| Beginner CAC via Reddit > $15 | Rotate to TikTok demo content (in-gym AI machine-coach demo is highly TikTok-native). |
| Marketplace fills <50% | Drop it from v1 and run AI-only at $9.99/mo until 2,000 subs. |
| Liability for injury advice | Disclaimers ("not medical advice"). Human escalation provides a trust escape hatch. |
