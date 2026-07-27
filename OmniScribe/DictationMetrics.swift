import Foundation

/// Timing breakdown of one dictation, measured the way latency is actually felt:
/// the clock starts at the **last spoken word**, not at ⌥Space. Time spent
/// speaking belongs to the user, not to the app, so including it would hide the
/// numbers that can actually be optimised.
struct DictationMetrics: Identifiable {
    let id = UUID()
    let startedAt = Date()

    /// How long the user spoke. Context for reading the other numbers, not latency.
    var spokenSeconds: TimeInterval = 0
    /// Last word → recording stopped (VAD silence wait, or a manual ⌥Space).
    var silenceWait: TimeInterval = 0
    /// Speech-to-text round trip.
    var transcription: TimeInterval = 0
    /// LLM reshaping. Zero when the stage was skipped.
    var aiProcessing: TimeInterval = 0
    /// Clipboard save → ⌘V → clipboard restore.
    var injection: TimeInterval = 0
    /// What happened: "Inserted", "No speech", an error label…
    var outcome: String = "—"

    /// The number that matters: last spoken word → text on screen.
    var perceivedLatency: TimeInterval {
        silenceWait + transcription + aiProcessing + injection
    }

    var succeeded: Bool { outcome == DictationMetrics.insertedOutcome }

    static let insertedOutcome = "Inserted"

    /// One-line console form, e.g. `silence 2.00s · stt 0.84s · ai 1.21s · paste 0.13s → 4.18s`.
    var consoleSummary: String {
        func f(_ v: TimeInterval) -> String { String(format: "%.2fs", v) }
        return "silence \(f(silenceWait)) · stt \(f(transcription)) · ai \(f(aiProcessing)) "
             + "· paste \(f(injection)) → total \(f(perceivedLatency)) [\(outcome)]"
    }
}

/// Keeps the most recent dictations so Settings → Diagnostics can show them.
///
/// This exists because console logs are invisible when the app is launched
/// normally from Finder — and launching from a terminal to read them attributes
/// Microphone/Accessibility to the *terminal*, which manufactures the very
/// failures you are trying to diagnose. In-app display is the only diagnostics
/// surface that works in the mode users actually run.
@MainActor
final class MetricsStore: ObservableObject {

    static let shared = MetricsStore()
    private init() {}

    @Published private(set) var recent: [DictationMetrics] = []

    private let maxEntries = 15

    func record(_ metrics: DictationMetrics) {
        recent.insert(metrics, at: 0)
        if recent.count > maxEntries {
            recent.removeLast(recent.count - maxEntries)
        }
    }

    /// Average perceived latency over successful dictations.
    var averageLatency: TimeInterval? {
        let values = recent.filter(\.succeeded).map(\.perceivedLatency)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Worst case — more actionable than the average when tuning.
    var slowestLatency: TimeInterval? {
        recent.filter(\.succeeded).map(\.perceivedLatency).max()
    }
}

// MARK: – Transcription sanity check

extension String {
    /// `true` when a transcription contains no actual words.
    ///
    /// Whisper hallucinates filler on silent or near-silent audio — most often
    /// music notes ("🎵🎵🎵"), ellipses, or a lone punctuation mark. Treating
    /// those as text means paying for an LLM call and pasting nonsense, so the
    /// pipeline stops here instead. A single letter or digit anywhere is enough
    /// to consider the result real speech.
    var looksLikeNoSpeech: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return !trimmed.unicodeScalars.contains {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }
    }
}
