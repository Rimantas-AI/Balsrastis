import Foundation

/// How much real signal a finished recording contained.
///
/// The distinction matters: "no audio is reaching the app at all" (missing
/// Microphone permission, wrong input device) and "the microphone is quiet but
/// working" look identical if you only ask whether speech crossed a threshold —
/// and rejecting the second case would lock out anyone with a quiet mic.
enum SignalQuality {
    /// Effectively digital silence — no audio is arriving. Worth stopping for.
    case silent
    /// Real signal, but nothing crossed the speech threshold. Still worth sending:
    /// the cloud recogniser is more sensitive than a fixed RMS threshold.
    case noSpeech
    /// Speech was detected.
    case speech
}

/// Detects when the user has stopped talking so recording can auto-stop, and
/// reports what kind of signal the microphone actually delivered.
///
/// Design notes:
/// - Operates on the **already-converted** 16 kHz mono stream, so silence is
///   measured in *samples*, not wall-clock time. This makes the detector fully
///   deterministic and independent of buffer scheduling jitter.
/// - Requires speech to have started at least once (`hasDetectedSpeech`) before
///   it will ever fire. Otherwise the very first silent buffers would stop a
///   recording before the user had a chance to speak.
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

    // MARK: – Init

    /// `true` when this detector ended the recording (as opposed to the user
    /// pressing ⌥Space a second time).
    var didAutoStop: Bool { hasFired }

    /// Silence budget default is 1.2 s, down from 2.0 s. Measurements showed the
    /// original wait was pure dead time on every auto-stopped dictation, while
    /// 1.2 s still tolerates the natural pause inside a sentence ("Parašyk
    /// klientui… kad rytoj neatvyksiu"). A second ⌥Space remains the instant stop.
    init(sampleRate: Double = 16_000,
         silenceThreshold: Float = 0.012,
         silenceDuration: TimeInterval = 1.2) {
        self.sampleRate         = sampleRate
        self.silenceThreshold   = silenceThreshold
        self.silenceDuration    = silenceDuration
        self.silenceSampleBudget = Int(silenceDuration * sampleRate)
    }

    // MARK: – Public API

    /// Arms the detector for a fresh recording. Call this in `start()`.
    func reset() {
        hasDetectedSpeech = false
        consecutiveSilentSamples = 0
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
            // Voice present – note it and clear any accumulated silence.
            hasDetectedSpeech = true
            lastSpeechAt = CFAbsoluteTimeGetCurrent()
            consecutiveSilentSamples = 0
            return
        }

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
