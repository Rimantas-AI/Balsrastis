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
                    HStack(spacing: 8) {
                        Button("Copy Report") { copyReport() }
                            .controlSize(.small)
                            .disabled(store.recent.isEmpty)
                        Button("Clear Diagnostics", role: .destructive) { clear() }
                            .controlSize(.small)
                            .disabled(store.recent.isEmpty)
                    }
                }
            }
            Text("Timings above are successful runs only.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func clear() {
        store.clear()
        showToast("Diagnostics cleared")
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

                Text(String(format: "spoke %.1f s", entry.spokenSeconds))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
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
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
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

// MARK: – General (mode + provider)

private struct GeneralSettingsView: View {
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        Form {
            Section {
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
            } footer: {
                Text("The processing mode is applied to every dictation until you change it. Activate dictation with \u{2325}Space.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
