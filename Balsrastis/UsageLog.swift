import Foundation

/// Append-only CSV record of dictation outcomes, for the week-long real-usage
/// validation (roadmap step 2).
///
/// Exists because `MetricsStore` lives in memory and dies with the app: a
/// question like "did a hallucination reach the document this week?" cannot be
/// answered from a 60-entry window that resets on every relaunch. A week of real
/// use needs something that survives quitting.
///
/// **Deliberately stores no dictated content.** Every field is a number, a
/// timestamp, or a fixed label — never the transcript, never the reshaped text,
/// never audio. A word *count* is recorded (it is what makes the speech-rate
/// figure meaningful) but not the words. This is what makes the log safe to
/// leave running for a week and safe to paste into a chat or an issue, and it is
/// the property to preserve if fields are ever added.
///
/// Off by default — see `AppPreferences.logUsageStatistics`.
actor UsageLog {

    static let shared = UsageLog()
    private init() {}

    /// `~/Library/Application Support/Balsrastis/usage-log.csv`.
    ///
    /// Application Support rather than the app bundle: the bundle is replaced
    /// wholesale on every update, which would throw the week's data away exactly
    /// when it is being collected.
    nonisolated static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("Balsrastis", isDirectory: true)
                   .appendingPathComponent("usage-log.csv")
    }

    private static let header = "timestamp,app_version,stt_model,mode,outcome,auto_stop,"
        + "spoke_s,above_threshold_s,longest_span_s,silence_s,stt_s,ai_s,paste_s,total_s,"
        + "words,words_per_second,ai_cleanup_rejected,failure_category\n"

    /// Appends one already-formatted row, creating the file and header on first
    /// use. Failures are printed and swallowed: a logging problem must never
    /// interrupt a dictation the user is waiting on.
    func append(_ row: String) {
        let url = Self.fileURL
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)

            try Self.rotateIfHeaderChanged(at: url)

            if !FileManager.default.fileExists(atPath: url.path) {
                try Self.header.write(to: url, atomically: true, encoding: .utf8)
            }

            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = row.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } catch {
            print("[UsageLog] ⚠️ Could not write the usage log: \(error.localizedDescription)")
        }
    }

    /// Moves an existing log aside when its header no longer matches the columns
    /// being written.
    ///
    /// Without this, adding a column silently corrupts the file: the header is
    /// only written when the file is created, so an existing log would keep its
    /// old header while gaining wider rows, and every parser would misalign every
    /// column after the new one. That is the worst kind of data loss — the file
    /// still opens, and the numbers are simply wrong.
    ///
    /// The old file is renamed rather than deleted. A week of collected runs is
    /// not something to discard because a column was added.
    private static func rotateIfHeaderChanged(at url: URL) throws {
        guard let existing = try? String(contentsOf: url, encoding: .utf8),
              let firstLine = existing.split(separator: "\n", maxSplits: 1).first
        else { return }

        guard firstLine + "\n" != header else { return }

        var archived = url.deletingPathExtension().path + "-previous"
        var suffix = 1
        while FileManager.default.fileExists(atPath: archived + ".csv") {
            suffix += 1
            archived = url.deletingPathExtension().path + "-previous\(suffix)"
        }
        try FileManager.default.moveItem(at: url, to: URL(fileURLWithPath: archived + ".csv"))
        print("[UsageLog] ℹ️ Log columns changed; previous log kept as \(archived).csv")
    }
}

extension DictationMetrics {

    /// One CSV row for `UsageLog`. Built on the caller's actor so the log actor
    /// only ever receives a `String` — no metrics value has to cross an isolation
    /// boundary, and no dictated text can travel with it.
    ///
    /// Text fields are reduced to a word count and a rate here, at the boundary,
    /// so that "the log holds no content" is enforced by this function rather
    /// than by remembering to be careful at each call site.
    func usageLogRow(appVersion: String) -> String {
        func n(_ v: TimeInterval) -> String { String(format: "%.2f", v) }

        let rate = spokenSeconds > 0
            ? String(format: "%.2f", Double(transcriptWordCount) / spokenSeconds)
            : ""

        let fields = [
            ISO8601DateFormatter().string(from: startedAt),
            appVersion,
            sttModel,
            mode,
            outcome,
            wasAutoStopped ? "auto" : "manual",
            n(spokenSeconds),
            n(aboveThresholdSeconds),
            n(longestAboveThresholdSeconds),
            n(silenceWait),
            n(transcription),
            n(aiProcessing),
            n(injection),
            n(perceivedLatency),
            String(transcriptWordCount),
            rate,
            aiCleanupRejection,
            failureCategory,
        ]

        // Quote every field: `outcome` and `ai_cleanup_rejected` are
        // human-readable labels that already contain spaces and could gain a
        // comma later, which would silently shift every following column.
        return fields.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                     .joined(separator: ",") + "\n"
    }
}
