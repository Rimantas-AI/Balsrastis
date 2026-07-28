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
        audio.onPreSpeechTimeout = { [weak self] in
            print("[AppDelegate] ⏱️ No speech within the pre-speech budget — stopping.")
            self?.finishDictation()
        }
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
        metrics.aboveThresholdSeconds = audioManager.aboveThresholdSeconds
        metrics.longestAboveThresholdSeconds = audioManager.longestAboveThresholdSeconds
        // Latency is measured from the last spoken word, not the hotkey press.
        metrics.silenceWait = max(0, stoppedAt - (audioManager.lastSpeechAt ?? stoppedAt))
        metrics.wasAutoStopped = audioManager.didAutoStop
        metrics.mode = AppPreferences.shared.selectedMode.displayName

        menuBarManager?.updateState(.processing)
        WindowManager.shared.updateHUD(phase: .transcribing)
        print("[AppDelegate] ⏹️ Recording stopped – \(samples.count) samples, signal: \(quality).")

        // Guard 1 (input side): speech was never confirmed, whether the recording
        // was auto- or manually stopped. Sending it anyway would cost a round trip
        // and — as measured — Whisper does not fail obviously on a brief noise
        // burst (keyboard click, desk knock): primed by the vocabulary prompt, it
        // can confidently hallucinate a fluent, grammatical sentence instead of
        // returning something obviously empty. That risk is judged to outweigh the
        // earlier design's goal of still giving the cloud recogniser a chance on
        // genuinely quiet speech (an update to that assumption, not an oversight).
        switch quality {
        case .silent:
            complete(metrics,
                     outcome: "No microphone signal",
                     failure: "No microphone signal — check Microphone permission and input device.")
            return
        case .noSpeech:
            complete(metrics,
                     outcome: "No speech confirmed",
                     failure: "No speech confirmed — check your microphone level, or speak a little longer.")
            return
        case .speech:
            break
        }

        let sttModelChoice = AppPreferences.shared.sttModel
        let vocabulary = AppPreferences.shared.vocabulary
        let isComparing = AppPreferences.shared.compareSTTModels
        let runID = metrics.id
        if isComparing {
            metrics.comparedModels = AppPreferences.availableSTTModels
            compareSTTModels(
                samples: samples,
                vocabulary: vocabulary,
                excluding: sttModelChoice,
                runID: runID
            )
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let sttStart = CFAbsoluteTimeGetCurrent()
                let result: STTResult
                do {
                    result = try await self.transcriptionService.transcribe(
                        samples: samples,
                        vocabulary: vocabulary,
                        model: sttModelChoice
                    )
                } catch {
                    // Record the primary's failure as a comparison row too, so a
                    // model that rate-limits or times out is visible next to the
                    // others rather than only as a generic run failure.
                    if isComparing {
                        MetricsStore.shared.recordComparison(
                            STTComparisonResult(model: sttModelChoice,
                                                isPrimary: true,
                                                duration: CFAbsoluteTimeGetCurrent() - sttStart,
                                                text: "",
                                                failure: error.localizedDescription),
                            forRun: runID)
                    }
                    throw error
                }
                metrics.transcription = CFAbsoluteTimeGetCurrent() - sttStart
                metrics.sttModel = sttModelChoice
                if AppPreferences.shared.captureTestText {
                    metrics.transcribedText = result.text
                }
                if isComparing {
                    MetricsStore.shared.recordComparison(
                        STTComparisonResult(model: sttModelChoice,
                                            isPrimary: true,
                                            duration: metrics.transcription,
                                            text: result.text,
                                            failure: nil),
                        forRun: runID)
                }
                print("[AppDelegate] 📝 Transcription (\(result.source.rawValue)): \"\(result.text)\"")

                // Guard 2 (output side, defense-in-depth): the recogniser can still
                // return filler such as "🎵🎵🎵" for the rare confirmed-speech
                // recording that Whisper nonetheless can't transcribe. Guard 1 now
                // catches the large majority of no-speech cases before this point.
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

                // Cleanup mode promises the same text with mistakes fixed. When
                // the model rewrites instead — most importantly when it *acts on*
                // a dictated instruction — insert what was actually said rather
                // than the invention. Only this mode; the others exist to rewrite.
                var textToInsert = processed
                if mode == .ltTyping,
                   let reason = ProcessingMode.cleanupRejectionReason(raw: result.text,
                                                                      processed: processed) {
                    textToInsert = result.text
                    metrics.aiCleanupRejection = reason
                    print("[AppDelegate] ⚠️ AI cleanup rejected (\(reason)) — inserting raw transcript.")
                }

                let injectStart = CFAbsoluteTimeGetCurrent()
                try await TextInjector.shared.inject(textToInsert)
                metrics.injection = CFAbsoluteTimeGetCurrent() - injectStart

                self.complete(metrics, outcome: DictationMetrics.insertedOutcome, failure: nil)
            } catch {
                self.complete(metrics,
                              outcome: "Failed",
                              failure: error.localizedDescription)
            }
        }
    }

    /// Sends the same captured audio to every *other* STT model, purely to fill in
    /// the Diagnostics comparison (`AppPreferences.compareSTTModels`).
    ///
    /// Deliberately fire-and-forget: these tasks are started alongside the primary
    /// transcription and nothing ever awaits them, so the text the user is waiting
    /// for is never delayed by the slowest model. Each result is filed against
    /// `runID` whenever it arrives, and a failure here is recorded and otherwise
    /// ignored — a secondary model rate-limiting must not break a dictation.
    ///
    /// The raw samples are reused as-is, which is the entire point: re-recording a
    /// phrase per model varies pronunciation, pace and mic distance, and would
    /// measure the speaker rather than the recogniser.
    private func compareSTTModels(samples: [Float],
                                  vocabulary: String,
                                  excluding primaryModel: String,
                                  runID: UUID) {
        for model in AppPreferences.availableSTTModels where model != primaryModel {
            Task { [weak self] in
                guard let self else { return }
                let start = CFAbsoluteTimeGetCurrent()
                do {
                    let result = try await self.transcriptionService.transcribe(
                        samples: samples,
                        vocabulary: vocabulary,
                        model: model
                    )
                    MetricsStore.shared.recordComparison(
                        STTComparisonResult(model: model,
                                            isPrimary: false,
                                            duration: CFAbsoluteTimeGetCurrent() - start,
                                            text: result.text,
                                            failure: nil),
                        forRun: runID)
                } catch {
                    MetricsStore.shared.recordComparison(
                        STTComparisonResult(model: model,
                                            isPrimary: false,
                                            duration: CFAbsoluteTimeGetCurrent() - start,
                                            text: "",
                                            failure: error.localizedDescription),
                        forRun: runID)
                }
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
