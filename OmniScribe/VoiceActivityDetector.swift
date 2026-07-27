import Foundation

/// How much real signal a finished recording contained.
///
/// `.silent` vs `.noSpeech` distinguishes *why* speech was never confirmed (no
/// signal at all, e.g. a missing Microphone permission, vs. real signal that
/// never sustained enough energy) purely for the message shown to the user.
/// Neither case reaches Whisper: a brief noise burst (keyboard click, desk
/// knock) that never sustains real speech energy has been observed to make
/// Whisper *confidently hallucinate* a fluent sentence built from the
/// vocabulary prompt, rather than fail obviously — so both cases are blocked
/// before spending an API call, not just the fully-silent one.
enum SignalQuality {
    /// Effectively digital silence — no audio is arriving.
    case silent
    /// Real signal, but speech was never confirmed (see `VoiceActivityDetector`'s
    /// leaky speech-confirmation accumulator).
    case noSpeech
    /// Speech was confirmed.
    case speech
}

/// Detects when the user has stopped talking so recording can auto-stop, and
/// reports what kind of signal the microphone actually delivered.
///
/// Design notes:
/// - Operates on the **already-converted** 16 kHz mono stream, so both silence
///   and speech-onset are measured in *samples*, not wall-clock time. This makes
///   the detector fully deterministic and independent of buffer scheduling jitter.
/// - Speech onset (`hasDetectedSpeech`) requires a **leaky accumulator** to cross
///   `speechConfirmationBudget`, not a single loud buffer — see `process(samples:)`.
///   This is what tells a real spoken word apart from a keyboard click.
/// - Requires speech to have started at least once (`hasDetectedSpeech`) before
///   the silence timeout will ever fire. Otherwise the very first silent buffers
///   would stop a recording before the user had a chance to speak.
/// - `onSilenceTimeout` fires exactly **once** per session; call `reset()` to arm
///   it again for the next recording.
final class VoiceActivityDetector {

    // MARK: – Tuning

    /// RMS amplitude below which a buffer is considered "silence".
    /// 0.012 works well for a normal desk mic; expose later via Settings.
    private let silenceThreshold: Float

    /// How many continuous seconds of silence trigger the timeout.
    private let silenceDuration: TimeInterval

    /// Sample rate of the incoming (converted) stream. Whisper mandates 16 kHz.
    private let sampleRate: Double

    /// Precomputed silence budget in samples (`silenceDuration * sampleRate`).
    private let silenceSampleBudget: Int

    /// How long speech energy must accumulate before onset is confirmed.
    private let speechConfirmationDuration: TimeInterval

    /// Precomputed confirmation budget in samples.
    private let speechConfirmationBudget: Int

    /// Peak below which the whole recording counts as digital silence rather than
    /// quiet speech. Deliberately far under `silenceThreshold`: a live microphone
    /// always carries some noise floor, so audio that never reaches even this
    /// level means nothing is arriving. Checked against the peak of the entire
    /// recording, never a single buffer, so a brief gap cannot trip it.
    private let nearZeroPeak: Float = 0.0005

    /// The HUD meter needs a readable level, not every audio buffer.
    private let levelInterval: CFAbsoluteTime = 1.0 / 12.0

    // MARK: – State

    private(set) var hasDetectedSpeech = false
    /// Loudest sample seen this session — the basis for `signalQuality`.
    private(set) var peakAmplitude: Float = 0
    /// When speech was last heard, for measuring latency from the last word.
    private(set) var lastSpeechAt: CFAbsoluteTime?

    /// Leaky accumulator toward `speechConfirmationBudget`: grows on every
    /// above-threshold buffer, decays (not resets) on a below-threshold one.
    /// Decaying rather than zeroing survives the brief energy dips that occur
    /// *inside* real speech (between syllables, at plosives) without letting a
    /// single loud, brief noise burst confirm speech on its own.
    private var candidateSpeechSamples = 0

    /// Cumulative above-threshold time across the whole recording, independent
    /// of whether it ever contributed to confirmation — the diagnostic evidence
    /// for telling a hallucinated short clip (a moment of noise, mostly silence)
    /// apart from a real dictation (sustained above-threshold time throughout).
    /// Named for exactly what it measures — an RMS crossing — not "voice",
    /// which a cough or a keyboard click would also cross.
    private(set) var aboveThresholdSampleCount = 0

    private var consecutiveSilentSamples = 0
    private var hasFired = false
    private var lastLevelEmit: CFAbsoluteTime = 0

    /// Called on the audio thread the first time `silenceDuration` of continuous
    /// silence is observed after speech. Hop to the main queue inside the closure.
    var onSilenceTimeout: (() -> Void)?

    /// Normalised 0…1 input level for the HUD meter, emitted ~12×/second.
    /// Called on the audio thread.
    var onLevel: ((Float) -> Void)?

    /// Verdict on the recording that just finished.
    var signalQuality: SignalQuality {
        if hasDetectedSpeech { return .speech }
        return peakAmplitude < nearZeroPeak ? .silent : .noSpeech
    }

    /// Cumulative above-threshold time across the whole recording, in seconds —
    /// see `aboveThresholdSampleCount`.
    var aboveThresholdSeconds: TimeInterval { Double(aboveThresholdSampleCount) / sampleRate }

    // MARK: – Init

    /// `true` when this detector ended the recording (as opposed to the user
    /// pressing ⌥Space a second time).
    var didAutoStop: Bool { hasFired }

    /// Silence budget default is 1.2 s, down from 2.0 s. Measurements showed the
    /// original wait was pure dead time on every auto-stopped dictation, while
    /// 1.2 s still tolerates the natural pause inside a sentence ("Parašyk
    /// klientui… kad rytoj neatvyksiu"). A second ⌥Space remains the instant stop.
    ///
    /// `speechConfirmationDuration` defaults to 250 ms: measured evidence showed
    /// a single ~64 ms buffer of noise (keyboard click, desk knock) was enough to
    /// set `hasDetectedSpeech = true` under the old single-buffer rule, starting
    /// the silence countdown on a recording that never actually contained speech
    /// — Whisper, primed by the vocabulary prompt, then confidently hallucinated
    /// a fluent sentence instead of failing obviously. 250 ms survives brief
    /// noise but any real spoken word — even a short "taip"/"ne" — comfortably
    /// clears it.
    init(sampleRate: Double = 16_000,
         silenceThreshold: Float = 0.012,
         silenceDuration: TimeInterval = 1.2,
         speechConfirmationDuration: TimeInterval = 0.25) {
        self.sampleRate         = sampleRate
        self.silenceThreshold   = silenceThreshold
        self.silenceDuration    = silenceDuration
        self.silenceSampleBudget = Int(silenceDuration * sampleRate)
        self.speechConfirmationDuration = speechConfirmationDuration
        self.speechConfirmationBudget = Int(speechConfirmationDuration * sampleRate)
    }

    // MARK: – Public API

    /// Arms the detector for a fresh recording. Call this in `start()`.
    func reset() {
        hasDetectedSpeech = false
        consecutiveSilentSamples = 0
        candidateSpeechSamples = 0
        aboveThresholdSampleCount = 0
        hasFired = false
        peakAmplitude = 0
        lastSpeechAt = nil
        lastLevelEmit = 0
    }

    /// Feed each converted buffer here. Cheap: one pass over the samples.
    func process(samples: [Float]) {
        guard !samples.isEmpty else { return }

        var sumOfSquares: Float = 0
        var peak: Float = 0
        for sample in samples {
            sumOfSquares += sample * sample
            let magnitude = abs(sample)
            if magnitude > peak { peak = magnitude }
        }
        let rms = (sumOfSquares / Float(samples.count)).squareRoot()

        if peak > peakAmplitude { peakAmplitude = peak }
        emitLevel(rms)

        guard !hasFired else { return }

        if rms >= silenceThreshold {
            aboveThresholdSampleCount += samples.count
            candidateSpeechSamples += samples.count
            if candidateSpeechSamples >= speechConfirmationBudget {
                hasDetectedSpeech = true
            }
            lastSpeechAt = CFAbsoluteTimeGetCurrent()
            consecutiveSilentSamples = 0
            return
        }

        // Decay, don't zero: a brief dip inside a real word (between syllables,
        // at a plosive) shouldn't erase progress already made toward confirmation.
        candidateSpeechSamples = max(0, candidateSpeechSamples - samples.count)

        // Silence only counts once the user has actually started speaking.
        guard hasDetectedSpeech else { return }

        consecutiveSilentSamples += samples.count
        if consecutiveSilentSamples >= silenceSampleBudget {
            hasFired = true
            onSilenceTimeout?()
        }
    }

    // MARK: – Helpers

    private func emitLevel(_ rms: Float) {
        guard let onLevel else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastLevelEmit >= levelInterval else { return }
        lastLevelEmit = now
        // Speech RMS sits well below 0.2, so scale against that for a lively meter.
        onLevel(min(1, rms / 0.2))
    }
}
