import Foundation

/// One STT model's answer to a single recording, for the same-audio comparison
/// mode (`AppPreferences.compareSTTModels`).
///
/// Holds the **raw** transcript, never the AI-reshaped text: the point is to
/// isolate what the recogniser heard. Reshaping only ever runs on the primary
/// model's text, so comparing final text would measure Claude, not STT.
struct STTComparisonResult: Identifiable {
    let id = UUID()
    let model: String
    /// The model whose text was actually reshaped and pasted (Settings → STT Model).
    let isPrimary: Bool
    /// Round trip for this model alone. Meaningful only in aggregate — a single
    /// cloud call's latency varies too much to rank models on.
    let duration: TimeInterval
    /// Raw transcript, or empty when the call failed.
    let text: String
    /// Error description when the call failed, `nil` on success. A secondary
    /// model failing is recorded and otherwise ignored — it must never affect
    /// the dictation the user is waiting on.
    let failure: String?
    /// Whether `text` would have been rejected by the output-side no-speech
    /// guard. Recorded because "returned 🎵🎵🎵" and "returned a real sentence"
    /// are very different comparison outcomes on the same noise clip.
    var looksLikeNoSpeech: Bool { failure == nil && text.looksLikeNoSpeech }
}

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
    /// Longest *continuous* above-threshold run. Collected as evidence for
    /// separating sustained speech from many short mechanical impulses (keyboard
    /// tapping totals a lot of above-threshold time without ever sustaining) —
    /// no guard uses it yet, deliberately.
    var longestAboveThresholdSeconds: TimeInterval = 0
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

    /// Models this run is being compared across, in Settings order. Empty unless
    /// `AppPreferences.compareSTTModels` was on. Kept separately from the results
    /// so Diagnostics can show a model as "Comparing…" while its call is still in
    /// flight — the models finish at different times, and a row that silently
    /// omits the slow one reads as "it returned nothing".
    var comparedModels: [String] = []
    /// Per-model results, appended as each call returns (any order).
    var sttComparison: [STTComparisonResult] = []

    /// Why the AI result was discarded and the raw transcript inserted instead
    /// (see `ProcessingMode.cleanupRejectionReason`), or empty when the AI output
    /// was used. Recorded so a rejection is never silent — text differing from
    /// what the AI produced must be explainable from the report alone.
    var aiCleanupRejection: String = ""

    /// `"2/3"`-style progress over the compared models, or empty when this run
    /// was not part of a comparison. Shown so "no results" is distinguishable
    /// from "results still arriving" — and so a report copied too early is
    /// obvious rather than looking like the feature did nothing.
    var comparisonProgress: String {
        guard !comparedModels.isEmpty else { return "" }
        return "\(sttComparison.count)/\(comparedModels.count)"
    }

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
        Longest continuous above-threshold span: \(f(longestAboveThresholdSeconds))
        Silence: \(f(silenceWait))
        STT: \(f(transcription))
        AI: \(f(aiProcessing))
        Paste: \(f(injection))
        STT model: \(sttModel)
        AI model: \(aiModel)
        Mode: \(mode)
        """
        if !aiCleanupRejection.isEmpty {
            block += "\nAI cleanup rejected: \(aiCleanupRejection) — inserted Raw STT"
        }
        if !transcribedText.isEmpty { block += "\nRaw STT: \(transcribedText)" }
        if !processedText.isEmpty { block += "\nFinal: \(processedText)" }

        if !comparedModels.isEmpty {
            let done = comparisonProgress
            block += "\nComparison status: \(done)"
                  + (sttComparison.count == comparedModels.count ? " complete" : " — still running")
        }

        for model in comparedModels {
            block += "\n  \(model)"
            guard let result = sttComparison.first(where: { $0.model == model }) else {
                block += " — comparing…"
                continue
            }
            if result.isPrimary { block += " (primary)" }
            block += "\n    Time: \(f(result.duration))"
            if let failure = result.failure {
                block += "\n    Failed: \(failure)"
            } else {
                block += "\n    Raw: \(result.text)"
                if result.looksLikeNoSpeech { block += "\n    (blocked as no speech)" }
            }
        }
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

    /// Sized to hold a full ~30-clip STT comparison round in one exportable
    /// report — splitting a test round across two Copy Reports invites
    /// transcription mistakes when the numbers are tallied. This is not the
    /// answer for the week-long/200-run validation, which needs persistence
    /// across relaunches, not just a bigger in-memory window.
    private let maxEntries = 60

    /// Comparison results that arrived before their run was recorded. The
    /// secondary STT calls run concurrently with reshaping and pasting, so a fast
    /// model can answer before the dictation it belongs to has finished — without
    /// this buffer that result would be dropped.
    private var pendingComparisons: [UUID: [STTComparisonResult]] = [:]

    func record(_ metrics: DictationMetrics) {
        var entry = metrics
        if let pending = pendingComparisons.removeValue(forKey: entry.id) {
            entry.sttComparison.append(contentsOf: pending)
        }
        recent.insert(entry, at: 0)
        if recent.count > maxEntries {
            recent.removeLast(recent.count - maxEntries)
        }
    }

    /// Files one model's comparison result against its own dictation.
    ///
    /// Matched by run id rather than "the newest entry": models finish at
    /// different times, so a slow answer from the previous dictation would
    /// otherwise be attributed to the current one.
    func recordComparison(_ result: STTComparisonResult, forRun runID: UUID) {
        if let index = recent.firstIndex(where: { $0.id == runID }) {
            recent[index].sttComparison.append(result)
        } else {
            pendingComparisons[runID, default: []].append(result)
        }
    }

    /// Wipes the history so a fresh test round starts from a clean slate.
    func clear() {
        recent.removeAll()
        pendingComparisons.removeAll()
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

    // MARK: – STT model comparison

    /// Per-model aggregates across every compared run in the history.
    ///
    /// Speed can't be judged from one call — cloud latency varies enough that a
    /// single sample ranks models by luck. These are the numbers to read after a
    /// full test round, and they exist so a 30-clip round isn't tallied by hand
    /// from the raw rows, which is where arithmetic slips would quietly pick the
    /// wrong default model.
    ///
    /// Accuracy is deliberately **not** scored here: judging whether a Lithuanian
    /// transcript is correct needs a human reading it against what was actually
    /// said. Only the mechanically countable failures are.
    struct STTModelSummary {
        let model: String
        let runs: Int
        let median: TimeInterval?
        let p95: TimeInterval?
        let slowest: TimeInterval?
        /// Calls that errored (rate limit, timeout, server error).
        let failures: Int
        /// Successful calls whose text the no-speech guard would have rejected.
        let noSpeechResults: Int
    }

    var sttModelSummaries: [STTModelSummary] {
        let compared = recent.filter { !$0.comparedModels.isEmpty }
        guard !compared.isEmpty else { return [] }

        return AppPreferences.comparisonVariants.map(\.label).compactMap { model in
            let results = compared.flatMap(\.sttComparison).filter { $0.model == model }
            guard !results.isEmpty else { return nil }
            let durations = results.filter { $0.failure == nil }.map(\.duration).sorted()
            return STTModelSummary(
                model: model,
                runs: results.count,
                median: Self.percentile(durations, 0.5),
                p95: Self.percentile(durations, 0.95),
                slowest: durations.last,
                failures: results.filter { $0.failure != nil }.count,
                noSpeechResults: results.filter(\.looksLikeNoSpeech).count
            )
        }
    }

    /// Nearest-rank percentile. Exact interpolation is false precision at the
    /// sample sizes involved (tens of runs, not thousands).
    private static func percentile(_ sorted: [TimeInterval], _ fraction: Double) -> TimeInterval? {
        guard !sorted.isEmpty else { return nil }
        let rank = Int((fraction * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank - 1, 0), sorted.count - 1)]
    }

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

        let summaries = sttModelSummaries
        if !summaries.isEmpty {
            lines.append("STT model comparison (same audio per run)")
            // Each arm now gets a different prompt, so a single "sent to every
            // model" line would misdescribe the run. Both prompt texts are
            // printed because the whole open question is which one to keep.
            lines.append("Full prompt (Settings \u{2192} Vocabulary):")
            lines.append(AppPreferences.shared.vocabulary)
            lines.append("Short prompt:")
            lines.append(AppPreferences.shortVocabulary)
            for summary in summaries {
                lines.append(
                    "\(summary.model) \u{2014} runs: \(summary.runs) \u{00B7} median: \(f(summary.median)) "
                    + "\u{00B7} P95: \(f(summary.p95)) \u{00B7} slowest: \(f(summary.slowest)) "
                    + "\u{00B7} failed: \(summary.failures) \u{00B7} no-speech: \(summary.noSpeechResults)"
                )
            }
            lines.append("Accuracy is not scored here \u{2014} read the per-run Raw lines below.")
            lines.append("")
        }

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
    ///
    /// See also `exceedsPlausibleSpeechRate(over:)`, which catches the opposite
    /// failure: far *too much* text for the audio's length.
    var looksLikeNoSpeech: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return !trimmed.unicodeScalars.contains {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }
    }

    /// `true` when this transcript holds more words than could physically have
    /// been spoken in `seconds` — the signature of a recogniser that returned
    /// something other than a transcription.
    ///
    /// Automates a cross-check previously done by hand (see the methodology notes
    /// in §12). Measured across a 30-clip Lithuanian round, real dictation ran
    /// 0.35–2.05 words/second at its fastest, so 4.0 leaves roughly double the
    /// headroom over the fastest real speech seen. Deliberately loose: falsely
    /// blocking a real dictation is worse than passing a rare bad one.
    ///
    /// This catches what the text checks cannot — a model echoing the vocabulary
    /// prompt back as its "transcript" (observed from `gpt-4o-mini-transcribe` on
    /// keyboard noise). That output is fluent and full of letters, so
    /// `looksLikeNoSpeech` passes it, but ~70 words attributed to a 10-second
    /// recording is not speech at any rate. It does **not** catch a short
    /// hallucinated sentence, which is plausibly paced — that stays open.
    func exceedsPlausibleSpeechRate(over seconds: TimeInterval) -> Bool {
        guard seconds > 0.5 else { return false }
        let words = split(whereSeparator: \.isWhitespace).count
        guard words > 8 else { return false }   // too few to judge a rate by
        return Double(words) / seconds > 4.0
    }
}
