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
    /// Raw transcript — empty when the call failed **and** when
    /// `AppPreferences.captureTestText` is off. Use `init(model:isPrimary:duration:transcript:failure:)`
    /// rather than setting this directly, so the capture gate cannot be skipped.
    let text: String
    /// Error description when the call failed, `nil` on success. A secondary
    /// model failing is recorded and otherwise ignored — it must never affect
    /// the dictation the user is waiting on.
    let failure: String?
    /// Whether the transcript would have been rejected by the output-side
    /// no-speech guard. Recorded because "returned 🎵🎵🎵" and "returned a real
    /// sentence" are very different comparison outcomes on the same noise clip.
    ///
    /// Stored rather than computed from `text`, because `text` is dropped when
    /// capture is off — deriving it then would report *every* arm as no-speech.
    /// The verdict is taken from the real transcript at creation time; only the
    /// words are discarded.
    let looksLikeNoSpeech: Bool

    /// Records one arm's answer, keeping the transcript only when the user has
    /// explicitly turned on test-text capture.
    ///
    /// The gate lives here rather than at export because the promise made in
    /// Settings is that daily use never holds dictated content — an export-time
    /// filter would still have kept every model's transcript in memory, and
    /// would have been easy to forget on the next surface that prints a result.
    ///
    /// `capturingText` is passed in rather than read from `AppPreferences` so a
    /// run's privacy mode is fixed when the dictation starts. Reading it here
    /// would let a setting changed mid-run apply to some arms and not others.
    init(model: String, isPrimary: Bool, duration: TimeInterval,
         transcript: String, capturingText: Bool, failure: String?) {
        self.model = model
        self.isPrimary = isPrimary
        self.duration = duration
        self.failure = failure
        self.looksLikeNoSpeech = failure == nil && transcript.looksLikeNoSpeech
        self.text = capturingText ? transcript : ""
    }
}

/// One cleanup model's answer to a single transcript, for the same-text
/// comparison mode (`AppPreferences.compareAICleanup`).
///
/// The mirror of `STTComparisonResult`, one stage later. Comparing cleanup models
/// is far cheaper than comparing recognisers, because the input here is *text*:
/// every model receives byte-identical input, so nothing about the speaker,
/// microphone or pace can confound the result the way a second take would.
struct AIComparisonResult: Identifiable {
    let id = UUID()
    let model: String
    /// The model whose output was actually pasted (the registered provider).
    let isPrimary: Bool
    let duration: TimeInterval
    /// Cleaned text — empty when the call failed **and** when
    /// `AppPreferences.captureTestText` is off. Set through the initialiser so
    /// the capture gate cannot be bypassed.
    let text: String
    /// Error description when the call failed, `nil` on success. A secondary
    /// model failing is recorded and otherwise ignored.
    let failure: String?
    /// Why `ProcessingMode.cleanupRejectionReason` would have discarded this
    /// output, or `nil`. Recorded because "is it faster" is the easy question and
    /// "does it start rewriting instead of correcting" is the one that decides
    /// whether a model is usable — the current rejection count is zero across 203
    /// real runs, so any rejection at all from a candidate is a signal.
    ///
    /// Computed from the real output before the capture gate drops it, so the
    /// quality signal survives even when the words do not.
    let rejectionReason: String?

    /// Records one candidate's answer, keeping the cleaned text only when the
    /// user has explicitly turned on test-text capture. Same reasoning as
    /// `STTComparisonResult.init` — the gate belongs at the source, not at export.
    init(model: String, isPrimary: Bool, duration: TimeInterval,
         output: String, capturingText: Bool, failure: String?, rejectionReason: String?) {
        self.model = model
        self.isPrimary = isPrimary
        self.duration = duration
        self.failure = failure
        self.rejectionReason = rejectionReason
        self.text = capturingText ? output : ""
    }
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

    /// How many words the recogniser returned. Recorded **always**, unlike the
    /// text itself: a count carries no content, and it is what makes the logged
    /// speech-rate figure meaningful when reviewing a week of real use — a run
    /// with an implausible rate is the trace a hallucination leaves behind.
    var transcriptWordCount: Int = 0

    /// Models this run is being compared across, in Settings order. Empty unless
    /// `AppPreferences.compareSTTModels` was on. Kept separately from the results
    /// so Diagnostics can show a model as "Comparing…" while its call is still in
    /// flight — the models finish at different times, and a row that silently
    /// omits the slow one reads as "it returned nothing".
    var comparedModels: [String] = []
    /// Per-model results, appended as each call returns (any order).
    var sttComparison: [STTComparisonResult] = []

    /// Cleanup models this run was sent to, and their answers. Same split as the
    /// STT pair above: the intended list is fixed at dictation time so an
    /// unfinished comparison reads as "still running" rather than "did not run".
    var comparedAIModels: [String] = []
    var aiComparison: [AIComparisonResult] = []

    /// Why the AI result was discarded and the raw transcript inserted instead
    /// (see `ProcessingMode.cleanupRejectionReason`), or empty when the AI output
    /// was used. Recorded so a rejection is never silent — text differing from
    /// what the AI produced must be explainable from the report alone.
    var aiCleanupRejection: String = ""

    /// Fixed label for why a run failed, empty when it did not — see
    /// `FailureCategory`. Never holds an error message, only a compile-time
    /// constant, so it is safe in a shareable log.
    var failureCategory: String = ""

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

        if !comparedAIModels.isEmpty {
            block += "\nCleanup comparison: \(aiComparison.count)/\(comparedAIModels.count)"
                  + (aiComparison.count == comparedAIModels.count ? " complete" : " — still running")
            for model in comparedAIModels {
                guard let r = aiComparison.first(where: { $0.model == model }) else {
                    block += "\n  \(model)\n    (waiting)"
                    continue
                }
                block += "\n  \(model)\(r.isPrimary ? " (primary, pasted)" : "")"
                block += String(format: "\n    Time: %.2f s", r.duration)
                if let failure = r.failure {
                    block += "\n    Failed: \(failure)"
                } else {
                    // Distinguish "withheld" from "the model returned nothing" —
                    // an empty line here would read as the latter.
                    block += r.text.isEmpty
                        ? "\n    (text not captured — enable Capture test text)"
                        : "\n    Out: \(r.text)"
                    if let reason = r.rejectionReason {
                        block += "\n    ⚠️ would be rejected: \(reason)"
                    }
                }
            }
        }

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
                if !result.text.isEmpty {
                    block += "\n    Raw: \(result.text)"
                } else if !result.looksLikeNoSpeech {
                    // Empty here means withheld, not "the recogniser heard
                    // nothing" — that case is covered by the line below.
                    block += "\n    (text not captured — enable Capture test text)"
                }
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
    private var pendingAIComparisons: [UUID: [AIComparisonResult]] = [:]

    func record(_ metrics: DictationMetrics) {
        var entry = metrics
        if let pending = pendingComparisons.removeValue(forKey: entry.id) {
            entry.sttComparison.append(contentsOf: pending)
        }
        if let pending = pendingAIComparisons.removeValue(forKey: entry.id) {
            entry.aiComparison.append(contentsOf: pending)
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

    /// Files one cleanup model's result against its own dictation. Same run-id
    /// matching as `recordComparison(_:forRun:)`, for the same reason.
    func recordAIComparison(_ result: AIComparisonResult, forRun runID: UUID) {
        if let index = recent.firstIndex(where: { $0.id == runID }) {
            recent[index].aiComparison.append(result)
        } else {
            pendingAIComparisons[runID, default: []].append(result)
        }
    }

    /// Wipes the history so a fresh test round starts from a clean slate.
    func clear() {
        recent.removeAll()
        pendingComparisons.removeAll()
        pendingAIComparisons.removeAll()
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

    /// Per-cleanup-model aggregate. **P95 is the number to decide on, not the
    /// median**: the AI stage's median is 1.79s out of a 4.33s total, so even a
    /// 30% median win is only ~12% end-to-end, while its tail (P95 3.45s, max
    /// 7.73s) is what makes the app feel stuck. `rejections` is the quality
    /// gate — it stands at zero across 203 real runs, so any value above zero
    /// from a candidate model is a signal, not noise.
    struct AIModelSummary: Identifiable {
        var id: String { model }
        let model: String
        let runs: Int
        let median: TimeInterval?
        let p95: TimeInterval?
        let slowest: TimeInterval?
        let failures: Int
        let rejections: Int
    }

    var aiModelSummaries: [AIModelSummary] {
        let compared = recent.filter { !$0.comparedAIModels.isEmpty }
        guard !compared.isEmpty else { return [] }

        let models = compared.flatMap(\.comparedAIModels)
        var seen = Set<String>()
        let ordered = models.filter { seen.insert($0).inserted }

        return ordered.compactMap { model in
            let results = compared.flatMap(\.aiComparison).filter { $0.model == model }
            guard !results.isEmpty else { return nil }
            let durations = results.filter { $0.failure == nil }.map(\.duration).sorted()
            return AIModelSummary(
                model: model,
                runs: results.count,
                median: Self.percentile(durations, 0.5),
                p95: Self.percentile(durations, 0.95),
                slowest: durations.last,
                failures: results.filter { $0.failure != nil }.count,
                rejections: results.filter { $0.rejectionReason != nil }.count
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
            "Balsraštis Diagnostics",
            "App version: \(bundleVersion)",
            "macOS: \(osVersion)",
        ]
        if let tester = SettingsView.testerName {
            lines.append("Tester: \(tester)")
        }
        lines.append(contentsOf: [
            "Attempts: \(recent.count) \u{00B7} Inserted: \(successfulRuns) \u{00B7} Blocked: \(blockedRuns)",
            "Successful runs only \u{2014} Average: \(f(averageLatency)) \u{00B7} Median: \(f(medianLatency)) \u{00B7} Slowest: \(f(slowestLatency))",
            "",
        ])

        let summaries = sttModelSummaries
        if !summaries.isEmpty {
            lines.append("STT model comparison (same audio per run)")
            // Each arm now gets a different prompt, so a single "sent to every
            // model" line would misdescribe the run. Both prompt texts are
            // printed because the whole open question is which one to keep.
            lines.append("Full prompt (Settings \u{2192} Vocabulary), sent to the \u{201C}full prompt\u{201D} arms only:")
            lines.append(AppPreferences.shared.vocabulary)
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

        let aiSummaries = aiModelSummaries
        if !aiSummaries.isEmpty {
            lines.append("Cleanup model comparison (same transcript per run)")
            for summary in aiSummaries {
                lines.append(
                    "\(summary.model) \u{2014} runs: \(summary.runs) \u{00B7} median: \(f(summary.median)) "
                    + "\u{00B7} P95: \(f(summary.p95)) \u{00B7} slowest: \(f(summary.slowest)) "
                    + "\u{00B7} failed: \(summary.failures) \u{00B7} would-be-rejected: \(summary.rejections)"
                )
            }
            lines.append("Decide on P95, not median: the AI stage is ~1.8 s of a ~4.3 s total, so a")
            lines.append("30% median win is only ~12% end to end \u{2014} the tail is what feels stuck.")
            lines.append("Quality is not scored here \u{2014} read the per-run Out: lines and compare them yourself.")
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
