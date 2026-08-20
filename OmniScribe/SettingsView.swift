import AppKit
import SwiftUI

/// Applies the grouped form style on macOS 13+, and leaves the default Form
/// appearance on macOS 12 (where `.formStyle` does not exist). Keeps the app
/// building for a 12.0 deployment target while still looking native on newer OSes.
private extension View {
    @ViewBuilder
    func groupedFormIfAvailable() -> some View {
        if #available(macOS 13.0, *) {
            self.formStyle(.grouped)
        } else {
            self
        }
    }
}

/// The root Settings window content: a native macOS tabbed interface.
///
/// Uses `TabView` + `Form` + native `Picker`s — no iOS-style `NavigationView`
/// or back buttons. The window itself (title bar, close button, size) is managed
/// by `WindowManager`; this view only supplies content and a fixed size.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }

            APIKeysSettingsView()
                .tabItem { Label("API Keys", systemImage: "key") }

            DiagnosticsSettingsView()
                .tabItem { Label("Diagnostics", systemImage: "stopwatch") }
        }
        // Resizable (not a fixed frame) so the Diagnostics tab can be enlarged to
        // read more rows or fit a wider screenshot — the window itself is made
        // resizable in WindowManager, which also enforces the matching minimum.
        .frame(minWidth: 650, idealWidth: 850, minHeight: 450, idealHeight: 650)
    }

    /// Set only on a closed-pilot copy, stamped into `Info.plist` after the
    /// build; every CI-built release ships this blank, so `nil` here also
    /// covers normal daily use and is not itself a signal of anything.
    /// Not private — `DictationMetrics.fullReport()` reads it too, so a leaked
    /// report is traceable the same way a leaked build is.
    static var testerName: String? {
        let name = (Bundle.main.infoDictionary?["OmniScribeTesterName"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

// MARK: – Diagnostics (per-stage timings)

/// Shows where the time actually goes, in the app itself.
///
/// Console output is only readable when the app is launched from a terminal —
/// and doing that attributes Microphone/Accessibility to the terminal, which
/// manufactures failures that do not exist in normal use. So the timings have to
/// be visible here.
private struct DiagnosticsSettingsView: View {
    @ObservedObject private var store = MetricsStore.shared
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var toast: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
            if let toast {
                Text(toast)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
            Divider()
            if store.recent.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 24) {
                stat("Median", store.medianLatency)
                stat("Average", store.averageLatency)
                stat("Slowest", store.slowestLatency)

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text("Attempts \(store.recent.count) \u{00B7} Inserted \(store.successfulRuns) \u{00B7} Blocked \(store.blockedRuns)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Capture test text", isOn: $prefs.captureTestText)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .font(.caption)
                        .help("Records the raw Whisper transcript and the AI-reshaped result for each run, so Copy Report can show what STT vs. AI actually changed. Off by default \u{2014} turn on only for a deliberate test round, then off again.")
                    Toggle("Log statistics to disk", isOn: $prefs.logUsageStatistics)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .font(.caption)
                        .help("Appends one row per dictation to a CSV file that survives quitting, so a week of real use can be reviewed. Numbers only \u{2014} timings, outcome, word count and speech rate. Never the dictated text and never audio.")
                    HStack(spacing: 8) {
                        if prefs.logUsageStatistics {
                            Button("Show Log") { revealLog() }
                                .controlSize(.small)
                        }
                        Button("Copy Report") { copyReport() }
                            .controlSize(.small)
                            .disabled(store.recent.isEmpty)
                        Button("Clear Diagnostics", role: .destructive) { clear() }
                            .controlSize(.small)
                            .disabled(store.recent.isEmpty)
                    }
                }
            }
            // The build identity was previously only reachable by exporting a
            // report — leaving no way to confirm in the app itself that a new
            // build actually replaced the old one, which matters because every
            // ad-hoc build has to be re-granted Accessibility and a failed
            // install looks identical to a successful one.
            Text("Timings above are successful runs only. \u{00B7} OmniScribe \(Self.appVersion) \u{00B7} macOS \(Self.osVersion)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)

            if let tester = SettingsView.testerName {
                Text("Testing build for \(tester)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }

            modelComparisonSummary
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    /// Per-model aggregates over the whole history. A single call's latency is
    /// mostly cloud noise, so models are only worth ranking across a full test
    /// round — and accuracy stays a human judgement made by reading the
    /// transcripts in the rows below, not something scored here.
    @ViewBuilder
    private var modelComparisonSummary: some View {
        let summaries = store.sttModelSummaries
        if !summaries.isEmpty {
            Divider()
            ForEach(summaries, id: \.model) { summary in
                Text("\(summary.model) \u{2014} \(summary.runs) runs \u{00B7} median "
                     + format(summary.median) + " \u{00B7} P95 " + format(summary.p95)
                     + " \u{00B7} failed \(summary.failures) \u{00B7} no-speech \(summary.noSpeechResults)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func format(_ value: TimeInterval?) -> String {
        value.map { String(format: "%.2f s", $0) } ?? "\u{2014}"
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "\u{2014}"
    }

    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private func clear() {
        store.clear()
        showToast("Diagnostics cleared")
    }

    /// Selects the log in Finder rather than opening it: a CSV double-clicked
    /// opens in whatever app claims the type, and the useful action here is
    /// finding the file to attach or inspect.
    private func revealLog() {
        let url = UsageLog.fileURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            showToast("No log yet \u{2014} it appears after the next dictation")
        }
    }

    private func copyReport() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(store.fullReport(), forType: .string)
        showToast("Report copied to clipboard")
    }

    /// Fades a brief confirmation so "cleared" / "copied" is visible without a
    /// modal dialog — these actions are non-destructive to app data (only the
    /// in-memory history), so a full confirmation prompt would be noise.
    private func showToast(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { toast = nil }
        }
    }

    private func stat(_ title: String, _ value: TimeInterval?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.map { String(format: "%.2f s", $0) } ?? "—")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Text("No dictations yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Press \u{2325}Space and speak — timings appear here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(store.recent) { entry in
                    MetricsRow(entry: entry)
                    Divider()
                }
            }
        }
    }
}

/// One dictation: the headline latency plus the stage breakdown that explains it.
private struct MetricsRow: View {
    let entry: DictationMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(String(format: "%.2f s", entry.perceivedLatency))
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(entry.succeeded ? .primary : .secondary)

                Text(entry.outcome)
                    .font(.caption)
                    .foregroundStyle(entry.succeeded ? Color.green : Color.orange)

                Spacer()

                Text(String(format: "spoke %.1fs \u{00B7} above-thr %.2fs \u{00B7} longest %.2fs",
                            entry.spokenSeconds,
                            entry.aboveThresholdSeconds,
                            entry.longestAboveThresholdSeconds))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            if !entry.aiCleanupRejection.isEmpty {
                Text("AI cleanup rejected (\(entry.aiCleanupRejection)) \u{2014} inserted the raw transcript")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                stage("silence", entry.silenceWait)
                stage("speech\u{2192}text", entry.transcription)
                stage("AI", entry.aiProcessing)
                stage("paste", entry.injection)
            }

            // Which settings produced this row — auto/manual stop explains why
            // `silence` is ~2s in one run and ~0.1s in the next.
            Text("\(entry.sttModel) \u{00B7} \(entry.aiModel) \u{00B7} \(entry.mode) \u{00B7} "
                 + (entry.wasAutoStopped ? "auto stop" : "manual stop"))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)

            if !entry.comparedModels.isEmpty {
                comparison
            }

            if !entry.comparedAIModels.isEmpty {
                cleanupComparison
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }

    /// The same transcript as cleaned by each candidate model. A model that would
    /// have had its output rejected is called out in orange — that is the quality
    /// signal, and it matters more here than the timing beside it.
    private var cleanupComparison: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cleanup comparison: \(entry.aiComparison.count)/\(entry.comparedAIModels.count)"
                 + (entry.aiComparison.count == entry.comparedAIModels.count ? " complete" : " \u{2014} still running"))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            ForEach(entry.comparedAIModels, id: \.self) { model in
                let result = entry.aiComparison.first { $0.model == model }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(model)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        if result?.isPrimary == true {
                            Text("primary")
                                .font(.system(size: 9))
                                .padding(.horizontal, 4)
                                .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                        }
                        Spacer()
                        if let result, result.failure == nil {
                            Text(String(format: "%.2f s", result.duration))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    if let result {
                        if let failure = result.failure {
                            Text(failure)
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        } else {
                            // "(empty)" would read as "the model returned
                            // nothing"; the text is simply not kept unless
                            // capture is on.
                            Text(result.text.isEmpty
                                 ? "(text not captured \u{2014} enable Capture test text)"
                                 : result.text)
                                .font(.system(size: 11))
                                .foregroundStyle(result.text.isEmpty ? .tertiary : .primary)
                                .textSelection(.enabled)
                            if let reason = result.rejectionReason {
                                Text("would be rejected: \(reason)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.orange)
                            }
                        }
                    } else {
                        Text("comparing\u{2026}")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(.top, 2)
    }

    /// The same audio as heard by each STT model. Models answer at different
    /// times, so one still in flight is shown as "comparing…" rather than being
    /// left out, which would read as an empty result.
    private var comparison: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Comparison status: \(entry.comparisonProgress)"
                 + (entry.sttComparison.count == entry.comparedModels.count ? " complete" : " \u{2014} still running"))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            ForEach(entry.comparedModels, id: \.self) { model in
                let result = entry.sttComparison.first { $0.model == model }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(model)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        if result?.isPrimary == true {
                            Text("primary")
                                .font(.system(size: 9))
                                .padding(.horizontal, 4)
                                .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                        }
                        Spacer()
                        if let result, result.failure == nil {
                            Text(String(format: "%.2f s", result.duration))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    comparisonText(for: result)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func comparisonText(for result: STTComparisonResult?) -> some View {
        if let result {
            if let failure = result.failure {
                Text("Failed: \(failure)")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            } else {
                if !result.text.isEmpty {
                    Text(result.text)
                        .font(.system(size: 11))
                        .textSelection(.enabled)
                } else if !result.looksLikeNoSpeech {
                    // Withheld, not "heard nothing" — the no-speech line below
                    // covers that case and would otherwise be contradicted.
                    Text("(text not captured \u{2014} enable Capture test text)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                if result.looksLikeNoSpeech {
                    Text("blocked as no speech")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
            }
        } else {
            Text("comparing\u{2026}")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func stage(_ name: String, _ value: TimeInterval) -> some View {
        Text("\(name) \(String(format: "%.2f", value))")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: – Shortcut recorder

/// Captures the next keypress and stores it as the dictation shortcut.
///
/// Recording rather than choosing from a list, because which combinations are
/// free depends on the apps this particular person runs — see `HotkeyCombo`.
/// The keys are read with a *local* monitor, which only fires while this window
/// is focused, and `HotkeyManager.isRecording` silences the global tap for the
/// duration so re-recording the current shortcut cannot start a dictation.
private struct ShortcutRecorderRow: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var rejected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Shortcut")
                Spacer()
                Text(isRecording ? "Press keys\u{2026}" : prefs.hotkey.displayName)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(isRecording ? .secondary : .primary)
                Button(isRecording ? "Cancel" : "Change\u{2026}") {
                    isRecording ? stop() : start()
                }
                if prefs.hotkey != .default {
                    Button("Reset") {
                        stop()
                        prefs.hotkey = .default
                    }
                }
            }

            if rejected {
                Text("Add \u{2318}, \u{2325} or \u{2303}. A shortcut without one would fire while you type.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if isRecording {
                Text("Press the combination you want, or Escape to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let advisory = prefs.hotkey.advisory {
                // Orange only when something documented already owns it — the
                // softer notes are information, not a warning.
                Text(advisory)
                    .font(.caption)
                    .foregroundStyle(prefs.hotkey.reservedBy == nil ? Color.secondary : Color.orange)
            } else {
                // The one thing true of every shortcut, stated once. Note what
                // it does *not* say: that this combination is free. Nothing here
                // knows that, and the last version's guesses at it were wrong.
                Text("OmniScribe takes this combination from every other app while it runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        guard monitor == nil else { return }
        isRecording = true
        rejected = false
        HotkeyManager.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            capture(event)
            return nil   // Consume, so the keypress never reaches the UI behind.
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        HotkeyManager.isRecording = false
    }

    private func capture(_ event: NSEvent) {
        // Escape on its own cancels; Escape *with* modifiers is a real choice.
        if event.keyCode == 53, HotkeyCombo.flags(from: event.modifierFlags).isEmpty {
            stop()
            return
        }
        guard let combo = HotkeyCombo(event: event) else {
            rejected = true    // Stay in recording mode so they can try again.
            return
        }
        prefs.hotkey = combo
        stop()
    }
}

// MARK: – General (mode + provider)

private struct GeneralSettingsView: View {
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        Form {
            Section {
                ShortcutRecorderRow()

                Picker("Processing Mode", selection: $prefs.selectedMode) {
                    ForEach(ProcessingMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker("AI Provider", selection: $prefs.selectedProvider) {
                    ForEach(AIProviderID.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                Toggle("Compare cleanup models", isOn: $prefs.compareAICleanup)
                    .help("Sends the same transcript to every cleanup model and shows all results in Diagnostics. Only the primary model's text is ever pasted. Doubles Anthropic usage \u{2014} for a deliberate test round, not daily use.")

                Picker("STT Model", selection: $prefs.sttModel) {
                    ForEach(AppPreferences.availableSTTModels, id: \.self) { model in
                        Text(AppPreferences.roleDescription(for: model)).tag(model)
                    }
                }

                Toggle("Compare STT models", isOn: $prefs.compareSTTModels)
                    .help("Sends each recording to every model at once, both with and without the vocabulary prompt, and shows their raw transcripts side by side in Diagnostics. Only the model selected above is reshaped and pasted, so dictation is not slowed down or changed.")
            } footer: {
                Text("The processing mode is applied to every dictation until you change it. Activate dictation with \(prefs.hotkey.displayName). The STT model above is the one whose text is actually inserted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if prefs.compareSTTModels {
                Section {
                    Label(
                        "Every recording is sent \(AppPreferences.comparisonVariants.count) times \u{2014} each model with and without the vocabulary prompt \u{2014} so OpenAI transcription usage is about \(AppPreferences.comparisonVariants.count)\u{00D7} higher, and every raw transcript is kept in Diagnostics. Turn this off after a test round.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                TextEditor(text: $prefs.vocabulary)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 70)
            } header: {
                Text("Vocabulary")
            } footer: {
                Text("Write this as a short sentence in the dictation language, mentioning the terms you expect — not a bare word list. This is a hint, not a strict dictionary, so keep it brief (15\u{2013}25 terms). Mainly helps English jargon spoken inside Lithuanian sentences (\u{201C}HUD\u{201D}, \u{201C}Keychain\u{201D}).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .groupedFormIfAvailable()
    }
}

// MARK: – API Keys (Keychain-backed)

private struct APIKeysSettingsView: View {
    var body: some View {
        Form {
            Section {
                ForEach(AIProviderID.allCases, id: \.self) { provider in
                    APIKeyRow(provider: provider)
                }
            } footer: {
                Text("Keys are stored in the macOS Keychain, never in plain text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .groupedFormIfAvailable()
    }
}

/// One provider's key field with Save / Remove, backed directly by `KeychainManager`.
private struct APIKeyRow: View {
    let provider: AIProviderID

    @State private var key: String = ""
    @State private var isStored: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(provider.displayName)
                    .font(.headline)
                Spacer()
                if isStored {
                    Label("Stored", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            SecureField("API Key", text: $key)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Save") { save() }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Remove", role: .destructive) { remove() }
                    .disabled(!isStored)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .onAppear(perform: load)
    }

    private func load() {
        // Flatten String?? from `try?` down to a plain String for the field.
        key = ((try? KeychainManager.shared.apiKey(for: provider)) ?? nil) ?? ""
        isStored = KeychainManager.shared.hasAPIKey(for: provider)
    }

    private func save() {
        try? KeychainManager.shared.setAPIKey(key.trimmingCharacters(in: .whitespaces), for: provider)
        isStored = KeychainManager.shared.hasAPIKey(for: provider)
    }

    private func remove() {
        try? KeychainManager.shared.deleteAPIKey(for: provider)
        key = ""
        isStored = false
    }
}
