import AVFoundation
import Foundation

/// Wraps AVSpeechSynthesizer with throttle + dedup so the user isn't spammed.
final class VoiceCoach {
    private let synth = AVSpeechSynthesizer()
    private var lastSpokenAt: Date = .distantPast
    private var lastUtterance: String = ""

    var isMuted: Bool = false

    func say(_ text: String) {
        guard !isMuted else { return }
        let now = Date()
        // Min 2.5s between announcements.
        guard now.timeIntervalSince(lastSpokenAt) > 2.5 else { return }
        // Never repeat the same cue within 6 seconds.
        if text == lastUtterance && now.timeIntervalSince(lastSpokenAt) < 6 { return }
        lastSpokenAt = now
        lastUtterance = text
        synth.stopSpeaking(at: .immediate)
        let utt = AVSpeechUtterance(string: text)
        utt.rate = 0.5
        utt.pitchMultiplier = 1.0
        utt.volume = 1.0
        if let voice = AVSpeechSynthesisVoice(identifier: AVSpeechSynthesisVoiceIdentifierAlex) {
            utt.voice = voice
        } else {
            utt.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        synth.speak(utt)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }
}
