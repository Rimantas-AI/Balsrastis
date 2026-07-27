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
    /// Cumulative above-threshold time across the recording — the evidence for
    /// telling a real dictation (sustained above-threshold time) apart from a
    /// brief noise burst that happened to trip the mic (e.g. `spoke 1.29s` /
    /// `above-threshold 0.06s` is a near-certain false trigger, not real speech).
    var aboveThresholdSeconds: TimeInterval = 0
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

    /// `true` when the VAD ended the recording, `false` when the user pressed
    /// ⌥Space again. Recorded so the silence figure can be read correctly — and
    /// so the measurement can be checked against what the user actually did.
    var wasAutoStopped = true

    /// Which processing mode ran, for comparing settings across runs.
    var mode: String = "—"
    /// Speech-to-text model used (e.g. `whisper-1`), for comparing STT models.
    var sttModel: String = "—"
    /// AI reshaping model used (empty when the AI stage was skipped).
    var aiModel: String = "—"

    /// Raw Whisper output and the AI-reshaped result. Populated only when
    /// `AppPreferences.captureTestText` is on — normal daily use never holds
    /// dictated content here at all, so there is nothing for a report to leak
    /// by default. See `reportBlock`.
    var transcribedText: String = ""
    var processedText: String = ""

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

    /// Plain-text block for one run inside a Copy Report export. The text lines
    /// appear only when they were actually captured (see `transcribedText`) —
    /// no separate export-time flag needed, since capture is the real gate.
    func reportBlock(index: Int) -> String {
        func f(_ v: TimeInterval) -> String { String(format: "%.2f s", v) }
        var block = """
        Run \(index) — \(outcome) — \(wasAutoStopped ? "Auto stop" : "Manual stop")
        Total: \(f(perceivedLatency))
        Spoke: \(f(spokenSeconds))
        Above threshold: \(f(aboveThresholdSeconds))
        Silence: \(f(silenceWait))
        STT: \(f(transcription))
        AI: \(f(aiProcessing))
        Paste: \(f(injection))
        STT model: \(sttModel)
        AI model: \(aiModel)
        Mode: \(mode)
        """
        if !transcribedText.isEmpty { block += "\nRaw STT: \(transcribedText)" }
        if !processedText.isEmpty { block += "\nFinal: \(processedText)" }
        return block
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

    /// Wipes the history so a fresh test round starts from a clean slate.
    func clear() {
        recent.removeAll()
    }

    /// Average perceived latency over successful dictations.
    var averageLatency: TimeInterval? {
        let values = recent.filter(\.succeeded).map(\.perceivedLatency)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Median latency — the honest "typical" figure. A single slow AI response can
    /// drag the average far above anything the user actually experiences, so this
    /// is the number to optimise against.
    var medianLatency: TimeInterval? {
        let values = recent.filter(\.succeeded).map(\.perceivedLatency).sorted()
        guard !values.isEmpty else { return nil }
        let mid = values.count / 2
        return values.count.isMultiple(of: 2)
            ? (values[mid - 1] + values[mid]) / 2
            : values[mid]
    }

    /// Worst case — more actionable than the average when tuning.
    var slowestLatency: TimeInterval? {
        recent.filter(\.succeeded).map(\.perceivedLatency).max()
    }

    var successfulRuns: Int { recent.filter(\.succeeded).count }
    /// Attempts the guards caught (no signal / no speech / a real failure) before
    /// they could cost an LLM call or paste something wrong.
    var blockedRuns: Int { recent.count - successfulRuns }

    /// Plain-text report for pasting into a chat or issue — the alternative to
    /// retyping numbers from a screenshot by hand. Includes transcribed/processed
    /// text automatically wherever it was captured (see `AppPreferences.captureTestText`);
    /// there is nothing to gate here since capture is the actual privacy boundary.
    func fullReport() -> String {
        func f(_ v: TimeInterval?) -> String { v.map { String(format: "%.2f s", $0) } ?? "—" }
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        var lines = [
            "OmniScribe Diagnostics",
            "App version: \(bundleVersion)",
            "macOS: \(osVersion)",
            "Attempts: \(recent.count) \u{00B7} Inserted: \(successfulRuns) \u{00B7} Blocked: \(blockedRuns)",
            "Successful runs only \u{2014} Average: \(f(averageLatency)) \u{00B7} Median: \(f(medianLatency)) \u{00B7} Slowest: \(f(slowestLatency))",
            "",
        ]
        for (index, entry) in recent.enumerated() {
            lines.append(entry.reportBlock(index: index + 1))
            lines.append("")
        }
        return lines.joined(separator: "\n")
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
