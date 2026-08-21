import AppKit
import SwiftUI

/// Shown once, on first launch, to let the user pick the dictation shortcut
/// before anything is taken from them.
///
/// The alternative — shipping a default and letting people discover the clash —
/// was tried and failed twice. ⌥Space was hardcoded until v1.6.12, and a reader
/// pointed out it is exactly the combination journalists, editors and
/// translators press deliberately for a non-breaking space. That is this app's
/// own audience. A later attempt to pick a "free" default instead ran into the
/// same wall from the other side: whether a combination is free depends on which
/// apps a particular person runs, which is not knowable from here.
///
/// So this asks. ⌥Space is still offered as one click, because it is what the
/// closest comparable app uses and it suits people who never touch a
/// non-breaking space — but taking it becomes a decision rather than a default.
struct FirstRunShortcutView: View {
    /// Called once the user has settled on a shortcut, so the window can close.
    var onDone: () -> Void

    @ObservedObject private var prefs = AppPreferences.shared
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var rejected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Pasirink diktavimo derinį")
                .font(.title2).bold()

            // One literal, not two joined with `+`: SwiftUI only parses Markdown
            // out of a static string, so concatenating printed the asterisks.
            Text("Balsraštis šį derinį **perims iš visų programų**, kol veiks. Todėl geriau pasirinkti tokį, kurio pats nenaudoji.")
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Text(isRecording ? "Spausk klavišus\u{2026}" : prefs.hotkey.displayName)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(isRecording ? .secondary : .primary)
                    .frame(minWidth: 130, alignment: .leading)

                Button(isRecording ? "Atšaukti" : "Įrašyti savo\u{2026}") {
                    isRecording ? stop() : start()
                }
            }

            Group {
                if rejected {
                    Text("Pridėk \u{2318}, \u{2325} arba \u{2303}. Be jų derinys suveiktų rašant.")
                        .foregroundStyle(.orange)
                } else if isRecording {
                    Text("Spausk norimą derinį arba Escape, kad atšauktum.")
                        .foregroundStyle(.secondary)
                } else if let advisory = prefs.hotkey.advisory {
                    Text(advisory)
                        .foregroundStyle(prefs.hotkey.reservedBy == nil ? Color.secondary : Color.orange)
                } else {
                    Text("Apie šį derinį nieko blogo nežinau — bet tai nereiškia, "
                         + "kad jis tikrai laisvas tavo programose.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            // The known collision is stated here rather than left to be found,
            // because the people most likely to hit it are the target users.
            Text("⌥Space yra įprastas pasirinkimas, bet juo rašomas **nelaužtinas tarpas** — jį sąmoningai naudoja žurnalistai, redaktoriai ir vertėjai. Jei esi vienas iš jų, rinkis kitą.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Naudoti ⌥Space") {
                    prefs.hotkey = .default
                    finish()
                }
                Spacer()
                Button("Gerai, tęsti") { finish() }
                    .keyboardShortcut(.defaultAction)
            }

            Text("Vėliau pakeisi: Settings → General → Shortcut.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 460)
        .onDisappear(perform: stop)
    }

    // MARK: – Recording

    private func start() {
        guard monitor == nil else { return }
        isRecording = true
        rejected = false
        HotkeyManager.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            capture(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        HotkeyManager.isRecording = false
    }

    private func capture(_ event: NSEvent) {
        if event.keyCode == 53, HotkeyCombo.flags(from: event.modifierFlags).isEmpty {
            stop()
            return
        }
        guard let combo = HotkeyCombo(event: event) else {
            rejected = true
            return
        }
        prefs.hotkey = combo
        stop()
    }

    private func finish() {
        stop()
        prefs.hotkeyChosen = true
        onDone()
    }
}
