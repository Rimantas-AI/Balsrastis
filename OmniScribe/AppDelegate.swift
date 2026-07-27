import AppKit

/// Central application lifecycle manager and dictation coordinator.
///
/// Responsibilities:
/// - Force `.accessory` activation policy so the app never appears in the Dock.
/// - Instantiate and own all top-level services in the correct order.
/// - Preload the Whisper model at launch so the first hotkey press is instant.
/// - Orchestrate one dictation cycle: hotkey → record → (VAD silence or hotkey) →
///   stop → transcribe → deliver text.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Strong references – these must live for the entire app lifetime.
    private var menuBarManager: MenuBarManager?
    private var permissionManager: PermissionManager?
    private var hotkeyManager: HotkeyManager?
    private var audioManager: AudioSessionManager?

    // Cloud STT (OpenAI Whisper) — supports Lithuanian and runs well on Intel
    // Macs, where Apple's Speech framework lacks Lithuanian and WhisperKit crashes.
    private let transcriptionService = CloudWhisperService()
    private let aiCoordinator = AILayerCoordinator.shared

    /// Guards against re-entrancy: the VAD timeout and a manual ⌥Space can both
    /// try to end the same recording.
    private var isDictating = false

    // MARK: – NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders: LSUIElement in Info.plist hides the Dock icon
        // at launch, but setting .accessory here guarantees it programmatically.
        NSApp.setActivationPolicy(.accessory)

        // 1. Status item must exist before anything else updates its icon.
        let mbm = MenuBarManager()
        menuBarManager = mbm

        // 2. Audio pipeline. Wire its callbacks to the dictation coordinator.
        let audio = AudioSessionManager()
        audio.onSilenceDetected = { [weak self] in self?.finishDictation() }
        audio.onError = { [weak self] error in self?.handleAudioError(error) }
        audio.onLevel = { level in WindowManager.shared.updateLevel(level) }
        audioManager = audio

        // 3. Preload the Whisper model now – NOT on the hotkey press – so the
        //    first dictation has zero model-load latency.
        Task { await transcriptionService.preloadModel() }

        // 4. Permissions – checked asynchronously so we never block the main thread.
        let pm = PermissionManager()
        permissionManager = pm

        Task { [weak self] in
            guard let self else { return }
            await pm.requestAllPermissions()

            // 5. Install global hotkey only after permission flow completes.
            //    HotkeyManager guards internally with AXIsProcessTrusted().
            self.hotkeyManager = HotkeyManager { [weak self] in
                self?.toggleDictation()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Never quit when (the non-existent) last window closes.
        return false
    }

    // MARK: – Dictation coordination

    private func toggleDictation() {
        if isDictating {
            finishDictation()
        } else {
            startDictation()
        }
    }

    private func startDictation() {
        guard !isDictating, let audioManager else { return }

        do {
            try audioManager.start()
            isDictating = true
            menuBarManager?.updateState(.listening)
            WindowManager.shared.showRecordingHUD(phase: .listening)
            print("[AppDelegate] 🎙️ Recording started.")
        } catch {
            print("[AppDelegate] ❌ Could not start recording: \(error.localizedDescription)")
            menuBarManager?.updateState(.idle)
            WindowManager.shared.showFailure(error.localizedDescription)
        }
    }

    private func finishDictation() {
        guard isDictating, let audioManager else { return }
        isDictating = false

        let stoppedAt = CFAbsoluteTimeGetCurrent()
        let samples = audioManager.stop()
        let quality = audioManager.signalQuality

        var metrics = DictationMetrics()
        metrics.spokenSeconds = Double(samples.count) / 16_000
        // Latency is measured from the last spoken word, not the hotkey press.
        metrics.silenceWait = max(0, stoppedAt - (audioManager.lastSpeechAt ?? stoppedAt))
        metrics.wasAutoStopped = audioManager.didAutoStop
        metrics.mode = AppPreferences.shared.selectedMode.displayName

        menuBarManager?.updateState(.processing)
        WindowManager.shared.updateHUD(phase: .transcribing)
        print("[AppDelegate] ⏹️ Recording stopped – \(samples.count) samples, signal: \(quality).")

        // Guard 1 (input side): no audio reached the app at all. Sending silence
        // would cost a round trip and come back as hallucinated filler, so stop
        // here and say what to fix. Only fires on effectively-zero signal —
        // a quiet-but-live microphone still goes through, because the cloud
        // recogniser is more sensitive than our fixed RMS threshold.
        if quality == .silent {
            complete(metrics,
                     outcome: "No microphone signal",
                     failure: "No microphone signal — check Microphone permission and input device.")
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let sttStart = CFAbsoluteTimeGetCurrent()
                let result = try await self.transcriptionService.transcribe(
                    samples: samples,
                    vocabulary: AppPreferences.shared.vocabulary
                )
                metrics.transcription = CFAbsoluteTimeGetCurrent() - sttStart
                metrics.sttModel = self.transcriptionService.model
                if AppPreferences.shared.captureTestText {
                    metrics.transcribedText = result.text
                }
                print("[AppDelegate] 📝 Transcription (\(result.source.rawValue)): \"\(result.text)\"")

                // Guard 2 (output side): the recogniser returns filler such as
                // "🎵🎵🎵" for silence. Never pay for an LLM call on that, and
                // never paste it. Catches the case Guard 1 cannot see — a live
                // but wrong input device produces real noise and no speech.
                guard !result.text.looksLikeNoSpeech else {
                    self.complete(metrics,
                                  outcome: "No speech recognised",
                                  failure: "No speech recognised — check your microphone input level.")
                    return
                }

                let mode = AppPreferences.shared.selectedMode
                WindowManager.shared.updateHUD(phase: .polishing)

                let aiStart = CFAbsoluteTimeGetCurrent()
                let processed = try await self.aiCoordinator.process(text: result.text, mode: mode)
                metrics.aiProcessing = CFAbsoluteTimeGetCurrent() - aiStart
                metrics.aiModel = self.aiCoordinator.activeModelIdentifier
                if AppPreferences.shared.captureTestText {
                    metrics.processedText = processed
                }
                print("[AppDelegate] ✨ Processed (\(mode.displayName)): \"\(processed)\"")

                let injectStart = CFAbsoluteTimeGetCurrent()
                try await TextInjector.shared.inject(processed)
                metrics.injection = CFAbsoluteTimeGetCurrent() - injectStart

                self.complete(metrics, outcome: DictationMetrics.insertedOutcome, failure: nil)
            } catch {
                self.complete(metrics,
                              outcome: "Failed",
                              failure: error.localizedDescription)
            }
        }
    }

    /// Records timings, returns to idle, and either dismisses the HUD or shows
    /// the failure in it.
    private func complete(_ metrics: DictationMetrics, outcome: String, failure: String?) {
        var finished = metrics
        finished.outcome = outcome
        MetricsStore.shared.record(finished)
        print("[AppDelegate] ⏱️ \(finished.consoleSummary)")

        menuBarManager?.updateState(.idle)

        if let failure {
            print("[AppDelegate] ❌ \(failure)")
            WindowManager.shared.showFailure(failure)
        } else {
            print("[AppDelegate] ⌨️ Inserted into the focused app.")
            WindowManager.shared.hideRecordingHUD()
        }
    }

    private func handleAudioError(_ error: AudioEngineError) {
        print("[AppDelegate] ⚠️ Audio error: \(error.localizedDescription)")
        isDictating = false
        menuBarManager?.updateState(.idle)
        WindowManager.shared.showFailure(error.localizedDescription)
    }
}
