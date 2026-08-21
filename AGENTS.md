# Balsraštis — Agent / LLM Handoff Guide

> Read this fully before changing anything. It captures **what the app is, how it
> works, why each key decision was made, and the traps that already cost days.**
> Written for another AI agent (or developer) picking up the project cold.

Repo: `https://github.com/Rimantas-AI/Balsrastis`

---

## 1. What Balsraštis is

A **menu-bar-only macOS app** for voice dictation with AI post-processing. The user
presses a global hotkey (**⌥Space** by default, changeable in Settings since
v1.6.13 — see `HotkeyCombo`), speaks, and cleaned-up text is **pasted into
whatever app currently has focus** (TextEdit, Mail, Slack, browser, this chat
box — anything).

The unique value: it doesn't just transcribe — it **reshapes** the text with an LLM
according to a selected *mode* (grammar cleanup, professional email, code snippet,
casual message, translation) before inserting it.

**Design principles:** invisible (no Dock icon, no window — only a menu-bar icon and
a small floating HUD while recording), universal (works in 100% of apps via
Accessibility + synthetic ⌘V), secure (API keys in Keychain), low-latency.

---

## 2. Runtime pipeline (the core loop)

Everything hangs off one cycle in `AppDelegate.finishDictation()`:

```
⌥Space (HotkeyManager, CGEventTap)
  → AudioSessionManager.start()           capture mic, convert to 16 kHz mono Float32
  → VoiceActivityDetector                 auto-stop after ~1.2 s of silence …
      OR ⌥Space again                     … or manual stop
  → AudioSessionManager.stop() → [Float]  the captured samples
  → CloudWhisperService.transcribe()      OpenAI Whisper API → Lithuanian text
  → AILayerCoordinator.process(text,mode) Claude (default) or OpenAI reshapes per mode
  → TextInjector.inject(processed)         save clipboard → set text → ⌘V → restore clipboard
  → back to idle, HUD hidden
```

States are shown via the menu-bar icon (`MenuBarManager`: idle / listening /
processing) and a floating panel (`WindowManager` + `HUDPanel` + `RecordingHUDView`).

Errors in the async pipeline are `catch`-ed, shown to the user in the HUD
(`HUDPhase.error`) and recorded in Settings → Diagnostics, which also exports a
full run history via **Copy Report**. They are `print`-ed with an ❌ prefix as
well, but **reaching for Terminal is now the wrong first move**: launching the
app from a terminal attributes Microphone and Accessibility to the *terminal*,
which manufactures failures that do not exist in normal use. Read Diagnostics
first; §7 is the fallback.

---

## 3. File / module map

**AppCore / lifecycle**
- `BalsraštisApp.swift` — `@main`, `Settings { EmptyView() }`, no `WindowGroup`.
- `AppDelegate.swift` — owns all services; orchestrates the dictation cycle. **Start here.**
- `MenuBarManager.swift` — `NSStatusItem`, 3-state icon, menu (Settings / Quit).
- `PermissionManager.swift` — requests Microphone + Accessibility, shows NSAlerts.
- `AppPreferences.swift` — `ObservableObject`, persists every non-secret choice in UserDefaults: mode, provider, STT model, vocabulary prompt, hotkey, and the three diagnostic toggles. **Never secrets** — those live in `KeychainManager`. Read once per run and snapshotted, see §12.

**Hotkey / OS interop**
- `HotkeyManager.swift` — global **CGEventTap**; **requires Accessibility**; guards with `AXIsProcessTrusted()`. Takes an `onTrigger` closure. Reads `AppPreferences.hotkey` live on every keypress, so a change applies without reinstalling the tap.
- `HotkeyCombo.swift` — the user's chosen shortcut (key code + modifiers + display name), recorded from a real keypress. **Read its header before touching the shortcut** — it explains why a list of suggested combinations was withdrawn.
- `TextInjector.swift` — `@MainActor`; clipboard-save → set string → synthesize ⌘V via `CGEvent` (`.cghidEventTap`) → `Task.sleep(120 ms)` → clipboard-restore. Requires Accessibility.
- `ClipboardState.swift` — deep-copies `NSPasteboardItem`s so text/image/file clipboard survives.

**Audio**
- `AudioSessionManager.swift` — `AVAudioEngine`, taps input, converts to 16 kHz mono Float32, feeds VAD; handles device changes; removes tap **before** stopping engine.
- `VoiceActivityDetector.swift` — RMS-based; only counts silence **after** it has first detected speech above threshold (0.012). Fires `onSilenceTimeout` once after ~1.2 s silence, and `onPreSpeechTimeout` after 6 s with no speech at all.
- `STTResult.swift` — provider-agnostic result `{ text, language, audioDuration, source }`.
- `AudioFixtures.swift` — saves each dictation as a 16 kHz WAV and replays it through the pipeline later, so a model comparison runs on **identical audio** instead of a fresh performance of the same sentences.

**STT (speech → text)**
- `CloudWhisperService.swift` — **THE ACTIVE TRANSCRIBER.** Uploads a 16 kHz mono WAV to the **OpenAI Whisper API** (`/v1/audio/transcriptions`, `language=lt`). Needs the **OpenAI** Keychain key.
- `LocalTranscriptionService.swift` — Apple `SFSpeechRecognizer` path. **Currently NOT wired into AppDelegate** (leftover). Apple Speech does **not** support `lt-LT`, so it can't do Lithuanian. Keep for reference / future non-Lithuanian on-device use, or delete.

**AI reshaping (text → text)**
- `AIProviderProtocol.swift` — `AIProviderProtocol { process(text:mode:) }`, `AIProviderID { claude, gemini, openai }`, `AIError`.
- `ProcessingMode.swift` — enum `{ ltTyping, email, code, messenger, translation }`, each carries a system prompt. `.ltTyping` = grammar cleanup keeping original language. Also holds `cleanupRejectionReason` — **the four rules that decide whether a reply may be pasted at all**.
- `TranscriptGuards.swift` — `looksLikeNoSpeech`, `exceedsPlausibleSpeechRate`, `echoesPrompt`, and the vocabulary prompt. Foundation-only on purpose: that is what lets `swift run GuardChecks` compile them without Xcode.
- `ClaudeService.swift` — Anthropic Messages API via raw `URLSession` (no Swift SDK). Model `claude-opus-4-8`. **No** temperature/top_p (rejected on Opus 4.7/4.8). 10 s timeout. Needs the **Claude** Keychain key.
- `AILayerCoordinator.swift` — factory routing to the selected provider. **`ClaudeService` and `OpenAIService` are registered**; Gemini is not, and `AIProviderID.implemented` is what the picker lists so an unimplemented choice can never be selected.
- `OpenAIService.swift` — the **single-key path**: cleanup via Chat Completions on the *same* Keychain entry the transcriber uses, so one account covers both steps. Read its header before changing the model — `gpt-4o-mini` was tried and changed a number.

**Security**
- `KeychainManager.swift` — generic-password CRUD keyed by provider `rawValue` under service `lt.balsrastis.app.apikeys` (with a one-time read-through to the pre-rename namespace, see the file). Keys **never** touch UserDefaults. **Per-machine** (keys do not travel with the app).

**Diagnostics / observability** (added v1.2.0 onward — the tooling every later
decision was made from; see §12)
- `DictationMetrics.swift` — per-run timing breakdown plus `MetricsStore` (in-memory history, 60 entries) and `fullReport()`, the **Copy Report** text. Dictated text is only ever held here when `captureTestText` is on, and is dropped at construction otherwise.
- `UsageLog.swift` — opt-in CSV appended to Application Support, surviving relaunch and app updates. **Numbers only, never words** — the reduction happens in `usageLogRow(appVersion:)`, at the boundary. Keep it that way if columns are added.
- `FailureCategory.swift` — classifies an error into a fixed label so the log records the *case* and never a server message, which can quote request content.

**UI**
- `SettingsView.swift` — native `TabView` (General + API Keys + Diagnostics) + `Form` + `Picker`. No iOS `NavigationView`. General: shortcut recorder, mode, provider, STT model, comparison toggles. API Keys: one `SecureField` per provider (Save/Remove), backed by Keychain. Diagnostics: timings, per-model summaries, Copy Report.
- `RecordingHUDView.swift` — SwiftUI HUD content (listening/processing).
- `HUDPanel.swift` — non-activating `NSPanel`, `.floating` level, `ignoresMouseEvents`, `canBecomeKey = false` (must never steal focus).
- `WindowManager.swift` — presents the Settings window, the first-run chooser and the HUD panel safely for an `LSUIElement` app.
- `FirstRunShortcutView.swift` — asks for the shortcut once, before the first dictation. Its header explains why picking a default failed twice.

**Tests**
- `Tests/GuardChecks/main.swift` — 31 checks over the guards above, every input a real transcript or reply from a test round. Deliberately **not XCTest** (which needs full Xcode); run with `swift run GuardChecks`. CI runs it before the Xcode build, together with `scripts/check-xcode-sources.sh`, which catches a new `.swift` file missing from `project.pbxproj` — a mistake that broke the build three times.

---

## 4. Hard-won decisions & WHY (do not "fix" these blindly)

1. **STT provider history — this is the most important lesson.**
   - Original plan: **WhisperKit** (on-device CoreML). **It crashes (SIGSEGV) on Intel Macs** — WhisperKit needs Apple-Silicon Neural Engine. The target user is on an **Intel** Mac → removed WhisperKit entirely (0 references now).
   - Tried **Apple `SFSpeechRecognizer`** — clean, no download, but **does not support Lithuanian (`lt-LT`)**. Returns empty for Lithuanian speech.
   - **Current: OpenAI Whisper API (cloud).** Supports Lithuanian, fast for short clips (~1–3 s), cheap, and — counter-intuitively — **faster than local Whisper on an Intel Mac** because the compute is off-device. This is why cloud beats "buy a local Whisper app" here.
   - ⚠️ If asked to "make transcription local/offline again": on Intel that means `whisper.cpp`, not WhisperKit, and it will be slow. Confirm the user's hardware first.

2. **Claude does NOT transcribe.** Anthropic has no audio modality. Claude only does step 2 (text→text reshaping). Never route audio to Claude. STT must be Whisper/Apple/whisper.cpp.

3. **Menu-bar only (`LSUIElement`).** No Dock icon, **no main window** — users repeatedly think it "didn't open"; it only shows a menu-bar icon. Floating HUD only during recording. Never add a `WindowGroup` as the primary UI.

4. **Hotkey via CGEventTap, not NSEvent monitor** — so ⌥Space can be *consumed* (not passed to the focused app). Requires **Accessibility**.

5. **Text injection via clipboard + synthetic ⌘V** (not Accessibility AXValue setting) — works reliably across all apps including sandboxed ones. Must restore the old clipboard **asynchronously** (sync restore pastes the old content).

6. **API keys in Keychain, per-machine.** They do **not** transfer when you copy the `.app` to another Mac — each machine must re-enter them in Settings.

7. **macOS 12.0 minimum, single universal build.** One build runs on 12 → 15 → newer (macOS is backward-compatible). Do **not** split into per-OS versions; use `if #available(...)` for newer-only APIs. WhisperKit removal is what allowed dropping the target from 14 to 12.

8. **App Sandbox is DISABLED** (`Balsraštis.entitlements`). CGEventTap + Accessibility + global paste can't work under the sandbox. Consequence: distribution is **Developer ID + notarization**, not the Mac App Store.

---

## 5. Build & distribution (no local Xcode — CI does it)

The user has **no full Xcode locally** (only Command Line Tools) and a modest Intel
Mac. All compiling happens on **GitHub Actions macOS runners**. Never assume a local
`xcodebuild`.

- Workflow: `.github/workflows/build.yml`. Trigger: push to `main` or manual dispatch.
- Runner `macos-15` + `maxim-lobanov/setup-xcode@v1 latest-stable` (a modern Xcode is required or SwiftPM resolution fails).
- Build command uses **`-scheme Balsrastis`** (a shared scheme exists at
  `Balsrastis.xcodeproj/xcshareddata/xcschemes/Balsraštis.xcscheme`). ⚠️ `-derivedDataPath`
  **requires** `-scheme`, not `-target` — this cost a failed build.
- `MACOSX_DEPLOYMENT_TARGET=14.0` was passed in CI while WhisperKit existed; the
  project target is now **12.0**. Keep CI override ≥ project target.
- Build is **unsigned** (`CODE_SIGNING_ALLOWED=NO`) then **ad-hoc signed**
  (`codesign --force --deep --sign -`) so it launches.
- Output: `Balsrastis.zip` uploaded as artifact **`Balsrastis-app`**. After WhisperKit
  removal the app is tiny (~0.3 MB) — models are not bundled; STT is cloud.

**To ship the built app to a user's Mac:** download the artifact (requires being
logged into GitHub), unzip twice → `Balsrastis.app`, then on the Mac:
`xattr -dr com.apple.quarantine /Applications/Balsrastis.app` (ad-hoc apps are
quarantine-blocked), then grant permissions.

**Verifying a CI run from a headless/agent context** (no `gh` auth): use the public
REST API, e.g.
`curl -s https://api.github.com/repos/Rimantas-AI/Balsrastis/actions/runs`
and `.../runs/{id}/jobs` for step results. Logs need auth (403 unauthenticated).

---

## 6. Permissions the app needs (and the #1 gotcha)

| Permission | Why | Where |
|---|---|---|
| **Microphone** | capture audio | Privacy → Microphone |
| **Accessibility** | CGEventTap hotkey **and** synthetic ⌘V paste | Privacy → Accessibility |
| **Speech Recognition** | only if using the Apple `LocalTranscriptionService` path (not the active OpenAI path) | Privacy → Speech Recognition |

**Gotcha — running from Terminal attributes permissions to Terminal, not Balsraštis.**
When you launch `…/Balsrastis.app/Contents/MacOS/Balsraštis` from a terminal to see
logs, macOS attributes Microphone/Accessibility to the **terminal app**. If the
terminal lacks Microphone permission, macOS feeds **silent (zero) buffers with no
error** → Whisper returns `"🎵🎵🎵"` (its silence hallucination) → VAD never detects
speech → auto-stop never fires. Fix: grant the terminal Microphone+Accessibility, **or**
just launch the `.app` normally from Finder for real use.

**Gotcha — ad-hoc signature changes every build.** Each new CI build has a different
ad-hoc signature, so macOS treats it as a new app and **Accessibility must be
re-granted** (remove the stale entry with "−", add the new `.app` with "+", relaunch).
This only disappears with a real Developer ID signature.

---

## 7. Debugging / testing

- Run from Terminal to see logs: `/Applications/Balsrastis.app/Contents/MacOS/Balsraštis`
  (mind the permission gotcha above — grant the terminal Mic+Accessibility).
- Log prefixes to grep: `[HotkeyManager]`, `[AppDelegate]`, `[CloudWhisperService]`.
  Key lines: `✅ Global hotkey ⌥Space registered`, `⏹️ Recording stopped – N samples`,
  `📝 Transcription (...)`, `✨ Processed (...)`, `⌨️ Inserted`, `❌ Pipeline failed: …`.
- `"🎵🎵🎵"` transcription = **silence/no speech reached Whisper** (mic not capturing;
  see permission gotcha, wrong input device, or background music).
- No auto-stop after silence = VAD never saw speech = same root cause (silent audio),
  or genuine mic level below the 0.012 RMS threshold.
- Multiple menu-bar mic icons = multiple instances (each Terminal launch spawns one);
  `killall Balsrastis`. NOTE: an isolated agent shell may not see the user's GUI
  processes — have the **user** run `killall`.
- Crash reports: `~/Library/Logs/DiagnosticReports/Balsraštis*.ips` (JSON; parse the
  `faultingThread` frames — that's how the WhisperKit SIGSEGV was pinpointed).

---

## 8. Known issues / TODO

- **Cosmetic mislabel:** `STTResult.Source` enum still reads `"Apple Speech (server)"`
  / `"Apple Speech (on-device)"`, but the active transcriber is **OpenAI Whisper**. Logs
  therefore say "Apple Speech (server)" when it's really OpenAI. Rename the enum values.
- **No user-facing error UI** — pipeline errors only `print`. Consider surfacing them in
  the HUD or a notification.
- **`LocalTranscriptionService` is dead code** in the current wiring (Apple has no
  Lithuanian). Either delete or keep behind a language/provider setting.
- **AI provider** — only Claude is implemented; `AILayerCoordinator` has stubs for
  Gemini/OpenAI-as-reshaper.
- **No "raw" dictation mode** — every mode runs the text through Claude, which edits it.
  `.ltTyping` cleans grammar (can slightly change wording). A pass-through mode that
  inserts the raw transcription (no LLM) would be a useful addition.
- **VAD sensitivity** is a fixed 0.012 RMS / 2 s. A quiet mic may never trip "speech
  detected". Consider a Settings slider.
- **Distribution friction:** ad-hoc signing → users need `xattr`/"Open Anyway" and
  re-grant Accessibility each build. Real fix = Apple Developer ID ($99/yr) +
  notarization + a `.dmg`/GitHub Release. Not done yet.
- **`gpt-4o-mini-transcribe` is an alias, not a pinned snapshot.** The entire STT
  decision rests on a name OpenAI can repoint without notice, and we would not
  notice: the usage log holds no text, so a quality regression would be invisible
  in the numbers. Before the pilot, check whether a dated snapshot id exists for
  it and pin it if so. If none exists, record that as an accepted risk rather
  than assuming stability. (The Anthropic side has the same issue and the fix is
  known — pin `claude-haiku-4-5-20251001`-style dated ids, never bare aliases.)
- **Two API keys required, per machine:** OpenAI (for STT) **and** Anthropic/Claude
  (for reshaping), entered in Settings → API Keys. Don't confuse the fields
  (`sk-...`/`sk-proj-...` = OpenAI; `sk-ant-...` = Claude). Swapping them → 401 on both.

---

## 9. Environment facts (this project's user)

- Two Macs: **Intel** MacBook Pro (macOS **15.7** Sequoia) and another on **macOS 12.7.6
  Monterey**. Both **Intel** → no WhisperKit, no Apple-Silicon assumptions.
- No local full Xcode. Builds run on GitHub Actions; the user downloads the artifact.
- Non-expert with the toolchain — give click-by-click steps (Finder/System Settings
  paths differ between Monterey "System Preferences" and Sequoia "System Settings").
- Primary dictation language: **Lithuanian** (`lt`). This is why OpenAI Whisper is
  mandatory (Apple lacks it).

---

## 10. If you extend it — where to look

- Add a language picker → `CloudWhisperService` (`language` param) + Settings General tab.
- Add a raw/no-LLM mode → new `ProcessingMode` case + short-circuit in
  `AppDelegate.finishDictation` (skip `aiCoordinator.process`).
- Add another AI provider → implement `AIProviderProtocol`, register it in
  `AILayerCoordinator.init(providers:)`.
- Notarized distribution → extend `.github/workflows/build.yml` with Developer ID
  signing + `notarytool` + a Release/`.dmg` step (needs the user's Apple credentials —
  the agent cannot supply them).
- Always: change code → commit → **user** does `git push` → CI builds → user downloads
  the new artifact and re-grants Accessibility.

---

## 12. Session history since Prompt 4 (v1.1.0 → v1.5.0) — READ THIS FIRST if picking up mid-project

The sections above describe the app as originally built. A long follow-up session
then did **real user testing with production diagnostics**, which changed several
defaults and fixed a real bug. If you're a fresh agent/session picking this up,
read this section before touching VAD, the vocabulary prompt, or the STT pipeline
— re-deriving these decisions from scratch will waste time and likely regress them.

**What shipped, in order:**
- v1.1.0 — longer timeouts (Whisper 120s, Claude 60s) for multi-sentence dictations.
- v1.2.0 — first Diagnostics tab: per-stage timing (`silence`/`stt`/`ai`/`paste`),
  input-side silence guard, HUD error surface, live level meter. Before this,
  failures only ever showed up in Terminal stdout, which is why v1.2.0 exists.
- v1.3.0 → v1.3.3 — the **vocabulary prompt saga**. Original hypothesis: English
  jargon in Lithuanian speech ("HUD", "Keychain") was being phonetically mangled
  by Whisper. Fixed by sending Whisper's `prompt` param — but the *first* version
  (a comma list) barely helped; a **short Lithuanian sentence naming the specific
  failing terms in context** (`AppPreferences.defaultVocabulary`) is what actually
  worked — **verified**, not assumed, by adding a `Raw STT:`/`Final:` split to
  Diagnostics (opt-in via `AppPreferences.captureTestText`, off by default —
  daily use never holds dictated text in memory) and re-running the same test
  script before/after. VAD silence timeout also dropped 2.0s → 1.2s here
  (measured as pure dead time on every auto-stopped run). Also added: median
  latency (average is skewed by rare ~15-20s cloud API latency spikes, ~1 in
  every 12-15 requests — accept this as normal cloud-API variance, not a bug to
  chase), Attempts/Inserted/Blocked counts, Copy Report (plain-text export of
  the whole Diagnostics history, for pasting into a chat/issue).
- v1.4.0 — STT model picker (Settings → General): `whisper-1` /
  `gpt-4o-mini-transcribe` / `gpt-4o-transcribe`, switchable at runtime, recorded
  per-run in Diagnostics.
- v1.5.0 — **the hallucination fix**, the most important bug found this session.
  A single ~64ms audio buffer above the RMS threshold (a keyboard click, a desk
  knock) was enough to set `hasDetectedSpeech = true` under the old single-buffer
  rule, starting the 1.2s silence countdown on a clip that never contained real
  speech. Whisper — primed by the vocabulary prompt — did not fail obviously on
  that clip; it **confidently hallucinated a fluent, grammatical Lithuanian
  sentence** built from prompt-adjacent phrases. Caught by cross-checking
  `Spoke:` duration against word count (a sentence needing 8+ real seconds to
  speak had `Spoke: 1.29s` — physically impossible). Fixed in
  `VoiceActivityDetector`: speech onset now requires ~250ms of *accumulated*
  above-threshold energy via a **leaky bucket** (`candidateSpeechSamples`) —
  grows on loud buffers, *decays* (not resets) on quiet ones, so a brief dip
  inside a real word doesn't wipe out progress, but an isolated brief noise
  burst can't confirm on its own. `AppDelegate` now blocks **both**
  `SignalQuality.silent` and `.noSpeech` before ever calling Whisper (previously
  only `.silent` blocked — `.noSpeech` used to still reach Whisper "to give the
  cloud recogniser a chance on quiet speech"; that assumption was deliberately
  reversed once hallucination-on-real-signal was proven, not silently changed).
  New `aboveThresholdSeconds` diagnostic (cumulative above-RMS-threshold time
  across the whole recording, named for exactly what it measures — not "voiced",
  since a cough or click also crosses the gate) is the evidence for telling a
  real dictation apart from noise.
  **Known residual edge case, accepted not fixed:** *sustained/repeated* noise
  (e.g. actual rapid keyboard tapping across many taps, not one click) can still
  net-accumulate past the 250ms leaky-bucket budget and reach Whisper — verified
  in testing. Whisper returned honest `🎵🎵🎵` filler for it, and the existing
  **output-side guard** (`String.looksLikeNoSpeech`, blocks empty/symbol-only
  transcripts) caught it before pasting. This is why both guards still exist —
  they are not redundant, they catch different failure modes (isolated blip vs.
  sustained noise).
  **250ms was regression-tested against short single-word utterances** ("taip",
  "ne", "gerai", "stop" — ~14 real trials) and none were falsely blocked
  (shortest real above-threshold reading: 0.49s, comfortably clear of 250ms) —
  do not lower it without new evidence of real words being blocked.
- v1.6.0 — **same-audio STT comparison mode** (Settings → General → "Compare STT
  models", off by default), the tooling for Roadmap step 1. One recording's
  `[Float]` samples are sent to all three models concurrently with identical
  `language=lt` and identical vocabulary `prompt`; each model's **raw** transcript,
  duration and error land in Diagnostics side by side. **Built and compiling, but
  the 30-clip comparison round itself is still the open next step** — no model
  choice has been made from evidence yet.
  Architecture rules that must not be "simplified" away:
  - The secondary calls are **fire-and-forget and nothing ever awaits them**
    (`AppDelegate.compareSTTModels`). Awaiting all three before reshaping would
    make every dictation as slow as the slowest model. Only the selected primary
    model's text is sent to Claude and pasted.
  - A secondary model failing (429/timeout/server error) is recorded as a
    comparison row and otherwise ignored — it must never break the dictation the
    user is waiting on. A *primary* failure is the normal user-visible error.
  - Results are filed against the run's `DictationMetrics.id`, never "the newest
    entry": models finish at different times, so a slow answer from the previous
    dictation would otherwise be attributed to the current one. Results that
    arrive before their run is recorded wait in `MetricsStore.pendingComparisons`.
  - Only raw STT text is compared, never Claude's output — otherwise the
    comparison measures the reshaper, not the recogniser.
  Also in this release: `MetricsStore.maxEntries` 15 → **60** (a 30-clip round
  must export as one Copy Report; tallying two half-reports by hand is where
  arithmetic slips would silently pick the wrong default model), per-model
  aggregate summary (runs / median / P95 / slowest / failures / no-speech counts)
  in both the Diagnostics header and Copy Report, and `Package.swift` fixed — it
  still declared the long-removed WhisperKit dependency, which made the local
  `swift build` type-check hang on dependency resolution instead of working.
  Accuracy is deliberately **not** auto-scored: judging a Lithuanian transcript
  needs a human reading it against what was actually said.
- v1.6.1 — **reliability fixes from the first real test round.** 26 clips were
  dictated on 2026-07-28 with the comparison toggle **off**, so that round is a
  whisper-1 baseline, not a model comparison (median 4.36s, 25/26 inserted). It
  found two product-level bugs that matter more than the model choice:
  1. **The keyboard-noise hallucination reached the user's app.** Typing on the
     keyboard with no speech produced *"Džiaugiuosi apie mūsų techninę diktaciją
     apie macOS programą"* — lifted almost verbatim from
     `AppPreferences.defaultVocabulary`, i.e. **our own prompt supplies the
     hallucination's content**. `Above threshold: 1.99s` over 7.29s cleared the
     250ms budget, and the output-side guard passed it because a fluent sentence
     contains letters. **This reverses the v1.5.0 note above**, which accepted
     this edge case on the evidence that Whisper returned honest `🎵🎵🎵` filler
     for sustained noise — it does not always, and both guards can fail together.
     Not yet fixed. `longestAboveThresholdSeconds` (longest *continuous*
     above-threshold run, vs. the existing cumulative total) was added as the
     evidence to build a real rule on: mechanical tapping is many short impulses,
     speech sustains through syllables. **No threshold is applied to it yet, on
     purpose** — do not invent one before there is data from both a real
     dictation and a keyboard-noise clip. ⚠️ A tempting-but-wrong fix is
     rejecting transcripts that resemble the vocabulary prompt: legitimate
     technical dictation ("HUD rodo būseną Listening, paskui Polishing")
     is *also* nearly verbatim from that prompt, and tested correct.
  2. **`.ltTyping` executed dictated instructions.** Dictating "Parašyk kolegai,
     kad susitikimas nukeliamas į rytojaus rytą" made Claude *write the email* —
     greeting, body, sign-off — and that was pasted. Fixed in two layers, since a
     prompt is guidance and not a guarantee: the `.ltTyping` system prompt now
     states the text is quoted content and never an instruction, and
     `ProcessingMode.cleanupRejectionReason` discards AI output that adds line
     breaks or grows the text disproportionately, inserting the raw transcript
     instead and recording `AI cleanup rejected` in Diagnostics. Cleanup mode
     only — every other mode is *meant* to rewrite.
- v1.6.2 — **the vocabulary prompt breaks the gpt-4o transcription models.**
  Found on the very first comparison runs, before the 30-clip round: given the
  standard Lithuanian vocabulary prompt, `gpt-4o-mini-transcribe` returned that
  **prompt back verbatim** as its "transcript" on two separate recordings, and
  `gpt-4o-transcribe` answered with sentences assembled from the prompt's subject
  matter that were never spoken (one of them — "Balsraštis transkribuoja jūsų
  balsą ir įrašo tekstą į dokumentą" — appears nowhere in the prompt at all).
  `whisper-1` transcribed the same audio correctly every time. The models do not
  interpret `prompt` the same way: whisper treats it as a spelling/style bias,
  the gpt-4o models treat it much more like context handed to a language model,
  so a long prompt invites echoing or paraphrase — most likely on short
  utterances, where there is little real speech to anchor the output.
  Consequence: **the original comparison design was not answerable.** Sending an
  identical prompt to all three is "fair" in the strict sense but only measures
  them under a setting that suits one of them, so the comparison was widened to
  six arms — each model **with and without** the vocabulary prompt
  (`AppPreferences.comparisonVariants`, `STTVariant`). Cost is ~6× STT per
  recording in this mode; it stays off by default.
  This also matters beyond model choice: the vocabulary prompt is what supplies
  the *content* of the keyboard-noise hallucination (see v1.6.1). A model that
  handles Lithuanian jargon well without any prompt would remove that failure
  mode at its source rather than guarding against it. Do not decide the default
  model from the with-prompt arms alone.
- v1.6.3 — **the 30-clip comparison round, and the decision it produced.**
  30 phrases × 6 arms = 180 transcripts of identical audio. Two hypotheses died
  and a default was chosen on evidence.
  **Dropping the prompt is not viable — this is settled, do not retry it.**
  Without a prompt, short Lithuanian words collapse into other languages:
  "Taip" came back as `طيب`, `Тайпа`, `Tey`, `ty`, `Tajba`; "Ne" as `네`, `Nie`;
  "Stop" as `Стоп`. `language=lt` alone does not hold the recogniser in
  Lithuanian on short audio — the prompt does. Removing it also bought **no
  speed** (mini: 0.72s with, 0.77s without). So the earlier hope of deleting the
  prompt to remove the hallucination's source is dead.
  **Default is now `gpt-4o-mini-transcribe`**, chosen because on the same audio:
  it was the most accurate on long sentences — `whisper-1` dropped a negation and
  turned "skaičiai **ne**sutampa" into "skaičiai sutampa", **inverting the
  meaning**, the worst error class in a dictation tool; it transcribed cleanly
  with real background music where `whisper-1` produced "Šitas **akinys** sakomas
  su **muzikafone**"; it got the technical terms right; and it was fastest with
  by far the tightest tail (median 0.72s / P95 1.19s / slowest **1.19s**, versus
  whisper-1's 1.09 / 1.66 / **6.48s**). `whisper-1` keeps one genuine advantage:
  it writes numbers as digits ("862-345-678", "Liepos 27-oji") where the gpt-4o
  models spell them out as words — unresolved, and the reason whisper-1 stays
  selectable rather than being removed.
  **`gpt-4o-transcribe` is demoted to experimental** and dropped from the
  comparison arms: it hallucinated fluent text from keyboard noise *even with no
  prompt at all* ("How are you doing?"), and its larger size bought nothing over
  the mini model on this material.
  **New guard: `String.exceedsPlausibleSpeechRate(over:)`.** `gpt-4o-mini` with
  the full prompt answers keyboard noise by echoing that prompt back verbatim —
  fluent, letter-rich text that `looksLikeNoSpeech` cannot catch, and ~400
  characters that would land in the user's document. Real dictation in this round
  ran 0.35–2.05 words/second; the echo was ~6.5. The threshold is 4.0 — roughly
  double the fastest real speech observed, deliberately loose because falsely
  blocking real dictation is worse than passing a rare bad transcript. It does
  **not** catch a short hallucinated sentence, which is plausibly paced.
  **Still open — the prompt's *form*.** The full prompt is prose, and whole
  sentences are exactly what gets echoed. A short term list
  (`AppPreferences.shortVocabulary`) might keep the language anchor without
  supplying that material. This is a hypothesis under test, **not** a conclusion:
  a bare comma list was already tried for whisper-1 in v1.3.x and barely helped —
  the sentence form is what worked there. So the comparison arms were re-pointed
  at this question: `gpt-4o-mini-transcribe` and `whisper-1` × {full, short,
  none}. Decide it from the next round, not from intuition.
  Also: the app and macOS version now appear in the Diagnostics tab, since build
  identity was previously only reachable by exporting a report — and every ad-hoc
  build needs Accessibility re-granted, so a failed install looks exactly like a
  successful one.
- v1.6.4 — **the prompt-form round: short prompt tested and rejected, model
  selection closed.** 15 clips, 6 arms. Everything held up, and one result
  reversed the intuition behind the whole idea.
  **The speech-rate guard did its job on first contact.** All three
  keyboard-noise clips were blocked (`Implausible speech rate`); the primary
  (`gpt-4o-mini-transcribe` + full prompt) echoed the vocabulary prompt back on
  every one of them, and none of it reached the document. Zero bad pastes.
  **The short prompt made things worse, not better.** It did keep short words
  accurate (`Taip` 4/4, `Ne` 5/5) — but it did not stop the echo, it only made
  the echo *shorter*: on identical noise, the full prompt came back at ~10.2
  words/second (over the 4.0 threshold, blocked) while the short prompt came back
  at ~2.77 (under it, would have been pasted — 18 words of junk). `whisper-1`
  with the short prompt answered the same noise with
  `[www.omniScribe.com](...)`, three times, likewise short enough to pass.
  **Shortening the prompt would have deleted the very signal the guard depends
  on.** Stated precisely — and the loose version of this claim was corrected in
  review, so do not restate it loosely: the long prompt is **not inherently
  safer**. It was safer *in these runs* only because its echo was long enough for
  the speech-rate guard to catch. A model could equally return one short excerpt
  from a long prompt, at a perfectly plausible pace, and slip through. That gap
  is what `String.echoesPrompt(_:)` was added to close in v1.6.5.
  A smaller point in the same direction: asked to transcribe a spoken "Na", only
  the full-prompt arm wrote `Na` — the short-prompt and whisper arms "corrected"
  it to `Ne`. The full prompt was the more faithful one.
  The 6s pre-speech timeout also fired correctly on both silence clips.
  **Next candidate guard, not yet built:** the sustain ratio
  `longestAboveThresholdSeconds / aboveThresholdSeconds` now separates the two
  classes — noise clips sat at 0.17–0.22, real speech at 0.38–1.0. That gap is
  real but rests on only four noise samples, and the current configuration
  already blocked 3/3 noise clips without it, so it stays unbuilt. Revisit only
  if a hallucination actually gets through.
- v1.6.7 — **week-long validation passed; `failure_category` added.**
  **203 real attempts across two Macs, 2026-07-29 → 08-06.** Primary Mac (132
  attempts over 7 days) against the roadmap's bar:

  | Bar | Target | Result |
  |---|---|---|
  | Hallucinated inserts | 0 | 0 detectable |
  | Falsely blocked speech | ≤1–2% | 0% (2 blocks, both correct) |
  | Median latency | ≤~5s | **4.33s** |
  | P95 not spiking to 15–20s | — | **7.15s**, max 11.67s |

  98.5% success (130/132). **Across all 203 attempts no guard fired a single
  false positive** — zero `Implausible speech rate`, zero `Prompt echoed back`,
  zero `AI cleanup rejected`, highest inserted speech rate 2.09 w/s against the
  4.0 limit. The guard stack is invisible in real use, which is what it was for.

  Latency composition, and the finding that should drive the next work: **AI
  cleanup is 44.3%** of total (median 1.79s, P95 3.45s, max 7.73s), STT 29.0%,
  VAD silence 23.8%, paste 2.9%. Local STT cannot fix the dominant cost — this is
  why a local-Whisper spike was proposed and declined.

  Read the numbers with three limits in mind, all of them real:
  1. **"Zero hallucinations" means zero *detectable*.** The log holds no text by
     design. A short, plausibly-paced hallucination would not show up here.
  2. **Usage was uneven**: 3/3/2/**105**/2/10/7 per day. Seven distinct days is a
     genuine retention signal, but the volume sits in one session — closer to a
     long test than to natural daily use. And one developer returning for seven
     days is not the same evidence as several independent users doing so.
  3. **The fan issue is now measured at 7.6%** (10/132) and it *biases the
     numbers optimistically*: those rows' median is 3.50s versus 4.41s for
     auto-stopped runs, because a manual stop skips the 1.2s silence wait and
     excludes the time spent noticing the app had not stopped. **True median is
     4.41s**, not 4.33s. Segment these rows out of any future analysis.

  `failure_category` was added to the log because the week could not explain its
  own failures: four runs on the secondary Mac (5.6% of that machine's attempts)
  recorded confirmed speech that produced no transcript, with no way to tell a
  network drop from a rejected key from a rate limit. The values are a **closed
  set of compile-time constants** — `FailureCategory` never reads an error's
  text, because server messages can quote request content or a key fragment and
  the log's whole value is that it can be shared without review. `unknown` exists
  so an unmapped failure is still visible as a failure rather than vanishing into
  an empty column.
  Adding that column also required log rotation: the header is written only at
  file creation, so an existing log would have kept its old header while gaining
  wider rows — every parser silently misaligning every column after the new one.
  `UsageLog.rotateIfHeaderChanged` renames the old file instead. **Any future
  column change must keep this working; a week of runs is not something to
  discard because a field was added.**
- ⚠️ **Two findings from real use that the test scripts missed. Read both
  before trusting a clean round.**

  **1. gpt-4o over-edits in natural dictation.** It passed a 22-phrase
  adversarial script — every number preserved, no command obeyed — and then, in
  ten dictations of ordinary work, changed meaning three times:
  `promtą` → `prašymą` (a *prompt* became a *request*, in a user whose work is
  prompts); `yra pakeitimai padaryti` → `ar pakeitimai padaryti`, turning a
  statement into a question; and `paraš pridėti … kad promptas` → `Pridėk … kad
  jis`. It also invented a word — `kasdienių darbą` → `kasdienių darbų sąrašą`.
  None tripped a guard: all are same-language, similar-length substitutions,
  the blind spot that has now cost four times.
  **An adversarial script and ordinary use test different things.** The script
  asks "will it do something forbidden"; daily use asks "will it leave alone
  what it was not asked to touch". gpt-4o answers the first well and the second
  badly. Claude was not compared on the same audio, so the honest claim is that
  this *happened*, not that Claude would have done better — the fixture replay
  in v1.10.0 exists to settle exactly that.

  **2. `gpt-4o-transcribe` fabricated a transcript from the vocabulary prompt.**
  Told "Sukurk sąrašą iš trijų punktų", it returned
  `1) Mac slaptažodis, 2) API raktas, 3) Keychain` — the first three terms of
  the vocabulary prompt, as **Raw STT**, before any cleanup ran. The recogniser
  executed an instruction it heard and answered from its own prompt.
  This is the documented reason it is not the default (see the v1.6.2 note); it
  recurred the moment the model was selected by hand. **Nothing catches it**:
  the text has letters, eight words over four seconds is a normal rate, it
  shares no long run with the prompt, and cleanup left it untouched so there was
  nothing to reject. A fabricated transcript reaching the document is currently
  guarded only by the user noticing.

- **Single-key mode settled (v1.8.0 → v1.10.0).** A reader with no Anthropic
  account asked whether one provider could do both jobs. It can — transcription
  already goes to OpenAI, so routing cleanup there too means one key instead of
  two — but the model choice took two rounds to get right.
  `gpt-4o-mini` **failed on the one criterion that matters**: asked only to
  punctuate "Butas devyniolika", it returned "Bet aštuoniolika" — nineteen
  became eighteen. Same class of failure as the Haiku-tier model in C1, and
  worse: Haiku reformatted numbers, mini changed a value. It also swapped
  "Butas" for "Bet" twice and restructured a sentence.
  `gpt-4o` passed twice, 22 phrases the second time: every number preserved,
  no false corrections on near-homophones, no restructuring, and all four
  command-phrased sentences returned as text. Two commas correctly added before
  "ir".
  ⚠️ But the first `gpt-4o` round produced **one English refusal that was
  pasted** ("I'm sorry, I can't assist with that."), and the second did not —
  same sentence, differing only by a colon versus a full stop in the transcript.
  **The failure is non-deterministic**, so the v1.9.2 language guard is what
  makes this path safe, not the model's good behaviour. Do not remove it on the
  strength of a clean round.
  Claude stays the default: it has 60 phrases behind it, this has 22.
- v1.6.14 — **the shortcut says what already owns it.** Recording ⌃Space,
  ⌘Space, ⌘Tab, a screenshot combination or Mail's ⌘⇧D now names the owner
  instead of leaving the collision to surface later.
  The list is documented Apple defaults plus one reported conflict, and the bar
  is deliberately that high — see v1.6.13 for why. **An absent combination means
  "nothing known", never "free", and the UI must never imply otherwise.** Keep
  that distinction if entries are added.
  Research also **reversed the plan to change the default**, which is worth
  recording because the instinct was to change it as penance for v1.6.12:
  Superwhisper ships ⌥Space as its default for the same job; ⌥Space's stock
  macOS behaviour is a non-breaking space users mostly hit by accident; and the
  language switcher it was suspected of stealing is actually **⌃Space**
  (⌃⌥Space for next). So people who switch layouts with ⌥Space remapped it
  themselves — the collision is real but narrower than the report implied. Both
  real input-source combinations are now in the list.
- v1.6.13 — **the shortcut is recorded, not chosen from a list.** v1.6.12 had
  shipped five suggested combinations, each annotated with what it "usually"
  conflicts with. Those annotations were guesses written as fact, and the
  reader broke two of five: ⌥Space (some users remap it to switch input
  sources) and **⌘⇧D, which is Send in Apple Mail** — an app this tool is
  specifically meant to dictate into.
  The fix was not a better list. Which combinations are free depends on the apps
  a particular person runs, which is not knowable from here, so the list was
  withdrawn entirely in favour of capturing the user's own keypress.
  Details that matter if this is touched: recording uses a *local* monitor and
  sets `HotkeyManager.isRecording`, so re-recording the current shortcut cannot
  start a dictation behind the Settings window; Shift alone is rejected as a
  modifier (⇧A is how a capital A is typed); and `displayName` is rendered once
  at record time from the key pressed, which avoids maintaining a
  keycode-to-character table per keyboard layout.
- v1.6.12 — **the shortcut became changeable at all.** Until here ⌥Space was
  hardcoded *and consumed* (`HotkeyManager` returns `nil`), so anyone using it
  to switch input sources lost that silently, with no way to change it — and
  that lands hardest on this app's own audience, who alternate between
  Lithuanian and English layouts all day. Reported by a reader, not found in
  testing. Superseded two releases later; kept in this history because the
  reason it existed is still the reason the recorder exists.
- v1.6.11 — **per-tester build stamping** (`BalsraštisTesterName` in
  `Info.plist`, blank in every CI build; the handout procedure is kept out of
  the public repo). Lets one CI
  build be stamped per tester in Terminal — no rebuild, no Xcode, no Apple
  Developer account. Settings and Copy Report then identify whose copy it is.
- v1.6.10 — **the cleanup benchmark became a true shadow test, and settings are
  snapshotted per run.** Both from review, before the C1 round rather than after
  it went wrong.
  The candidate models used to be fired *alongside* the production call, on the
  reasoning that "started early costs the user nothing". That reasoning was
  wrong in one specific way: three requests on one API key at once means a `429`
  provoked by the benchmark could fail the very dictation the user is waiting
  for. **A diagnostic must not be able to degrade the thing it measures.** The
  candidates now run *after* the text has been pasted.
  Concurrency bought nothing here anyway. The STT comparison genuinely needs the
  same audio because a second take differs in pace and mic distance; the cleanup
  comparison feeds every arm byte-identical *text*, so it stays fair whenever it
  runs. The incumbent is no longer re-called at all — its row comes from the
  production request, which is both the honest number under real conditions and
  one fewer request. A C1 run is now 1 normal call + 1 candidate, not 3 at once.
  **Settings are snapshotted once per run** (`capturingText`, `comparingCleanup`,
  `mode`, model, vocabulary). Previously the comparison structs read
  `AppPreferences.shared.captureTestText` at construction, deep inside async
  arms that finish out of order — a setting toggled mid-run could have applied
  to some arms and not others on the *same* dictation. A run now has exactly one
  privacy mode for its whole life. This also removes a hidden global dependency
  from two value types, which is why the flag is a parameter and not a lookup.
- v1.6.9 — **comparison results now honour the capture gate.** Found by reviewing
  the v1.6.7–v1.6.8 diff, not by a failure.
  Settings promises that dictated content is only ever kept when "Capture test
  text" is on, and `reportBlock`'s own comment stated it: *"capture is the real
  gate"*. Both comparison modes broke that. `STTComparisonResult.text` (since
  v1.6.2) and `AIComparisonResult.text` (v1.6.8) stored the full transcript and
  the full cleaned output regardless, so turning on a comparison **without**
  capture still produced a Copy Report containing every model's version of what
  was said. The CSV usage log was never affected — it holds no comparison fields
  at all — so this was a Copy Report leak, not a log leak.
  Fixed at the **source**, not at export: both structs now take the text through
  an initialiser that drops it unless capture is on, so the words never enter
  memory. An export-time filter would have kept them in memory and would have
  had to be remembered again on the next surface that prints a result.
  Two details worth keeping if this code is touched: `looksLikeNoSpeech` became a
  *stored* property, because computing it from a dropped `text` would have
  reported every arm as no-speech; and empty text now renders as "(text not
  captured)" rather than "(empty)", which read as "the model returned nothing".
  ⚠️ Still true and accepted: a comparison round issues 3 Claude calls (primary +
  2 candidates) and 6 STT calls on one key. A `429` caused by the diagnostic
  would hit the *primary* call too and fail a real dictation. Acceptable for a
  deliberate test round; `failure_category` now makes it visible as `rate_limited`.
- v1.6.6 — **on-disk usage log** (`UsageLog`, Settings → Diagnostics → "Log
  statistics to disk", off by default), the last thing missing before roadmap
  step 2. `MetricsStore` is memory-only and resets on relaunch, so "did a
  hallucination reach the document this week?" was unanswerable; the log survives
  quitting and app updates (it lives in Application Support, not the bundle,
  which is replaced wholesale on every install).
  **It stores no dictated content by construction.** Every field is a number, a
  timestamp or a fixed label. A word *count* is recorded — it is what makes the
  speech-rate column meaningful — but never the words. The reduction happens in
  `DictationMetrics.usageLogRow(appVersion:)`, at the boundary, so the property
  holds by design rather than by remembering to be careful at each call site.
  Keep it that way if columns are added.
  Kept separate from `captureTestText` deliberately: that switch governs whether
  dictated *content* sits in memory, this one whether *statistics* reach disk.
  Merging them would make a week-long measurement impossible without also
  recording everything the user said.
  Blocked runs are logged too — a log of successes only would answer the easy
  half of the question and hide the half that matters.
- v1.6.5 — **direct prompt-echo guard** (`String.echoesPrompt(_:)`), plus the
  correction above. The speech-rate guard only catches recitation while it stays
  long enough to be impossible speech; a partial echo is not, so the recitation
  itself is now detected directly.
  It matches the **longest contiguous run of words** shared with the prompt, not
  word overlap. Overlap is the obvious design and it is wrong: real technical
  dictation reuses these exact words — "HUD rodo būseną Listening, paskui
  Polishing" shares nearly its whole vocabulary with the prompt and is a correct,
  deliberate dictation. Sequence is what separates recitation from speech.
  The threshold (12) was checked against every transcript from the test rounds
  rather than picked: the full-prompt echo ran **57 words** unbroken, real
  dictation reached at most **7**. That worst case is genuine, not a fluke — the
  user dictated "Klaidos pranešimas gali būti „No microphone signal"", which is
  verbatim in the prompt because the prompt was written from the app's own
  vocabulary. An initial threshold of 8 was rejected for leaving only one word of
  margin over it.
  Known limits, both accepted: a user *can* legitimately dictate a whole prompt
  sentence and would be blocked; and this catches recitation, not invention — a
  model answering noise with one short plausible sentence of its own still
  defeats every guard here.
  Also: `shortVocabulary` was **deleted**, not merely commented as rejected.
  A rejected prompt sitting beside the live one invites a future reader to
  conclude the shorter one looks cleaner; the negative result belongs in this
  document, not in the production config.
- Also in v1.6.1: a **6s pre-speech timeout** in `VoiceActivityDetector`
  (`onPreSpeechTimeout`). The silence timeout only arms after speech onset, so a
  recording with no speech ran until stopped by hand (measured: 13.99s). It will
  not fire while an above-threshold run is accumulating, so someone who starts
  talking just before the deadline is not cut off mid-word. VAD's 1.2s silence
  and 250ms confirmation are **unchanged** — do not retune them as part of this.

**Methodology established this session (apply it going forward):**
- Never trust a narrated summary of what a model transcribed — get the literal
  `Raw STT:`/`Final:` text via `captureTestText`. A user's own paraphrase of
  "what it got wrong" is a different, less reliable signal than the actual bytes.
- Cross-check `Spoke:` (wall-clock recording duration) against word count when a
  result looks suspicious — real Lithuanian dictation speech runs roughly
  1.5-1.8 words/second at a deliberate dictation pace; a big mismatch is a strong
  hallucination/false-trigger signal, not something to hand-wave.
  Do NOT re-record the same test phrase per STT model to compare them — different
  takes have different pronunciation/pace/mic distance, which confounds the
  comparison. Same-audio-multiple-models is the only valid comparison design (see
  Roadmap).
- Median latency, not average, is the number to optimize against — rare cloud
  API latency spikes (~15-20s, both STT- and AI-side observed) skew the average
  without reflecting typical experience.
- Ship small, reversible, evidence-driven changes — every VAD/prompt change in
  this history was made *after* measured evidence, not intuition, and every
  release shipped independently testable so a regression is easy to isolate.

**Known open gaps (not yet built, deliberately deferred):**
- **Continuous background noise disables auto-stop.** Confirmed in real use on
  2026-07-29, day one of the usage log: a laptop fan spinning up holds the input
  above the 0.012 RMS threshold *continuously*, so speech is confirmed, silence
  never occurs, and neither the 1.2s silence timeout nor the 6s pre-speech
  timeout can fire. The recording runs until the user presses ⌥Space. Signature
  in the log: `above_threshold_s ≈ spoke_s` **and** `auto_stop = manual` **and**
  `silence_s ≈ 0` (observed: 9.49 / 9.49 / 0.02).
  Note the measurement consequence — `silenceWait` is computed from the last
  above-threshold moment, which under continuous noise is the instant the user
  stopped, so `total_s` on these rows is *optimistically biased*: it omits the
  time spent noticing the app had not stopped. **Segment these rows out before
  computing median/P95 for the week.**
  Measured at **7.6% of runs** (10/132) over the validation week. Still not
  fixed, and an independent review agreed: it is one machine in one acoustic
  environment, manual ⌥Space works, and the guard chain is currently stable and
  verified. Revisit if the pilot shows it across several users' machines or above
  ~5% of their dictations. Until then it belongs in onboarding, not in the VAD:
  *"If continuous background noise stops the recording from ending on its own,
  press ⌥Space again."*
  The obvious fix — an adaptive threshold derived from the ambient floor — has a
  nasty failure mode: estimated from a recording with
  no quiet moments, the floor rises to speech level, everything then counts as
  silence, and sentences get cut off mid-word. Designing that from a single
  sample is exactly the mistake this project's VAD history warns against. The
  week's `auto_stop` column will show how often it actually happens; decide from
  that. If it turns out frequent, the direction to explore is silence measured
  *relative to a running noise floor* rather than an absolute RMS value, with the
  floor only trusted once a genuinely quiet period has been observed.
- ~~Diagnostics history is memory-only~~ — solved in v1.6.6 by `UsageLog`. The
  in-app Diagnostics list is still a 60-entry memory window; the CSV is the
  durable record. No log rotation exists: ~200 runs is about 30 KB, so this only
  matters if the log is left on for months.
- P95 exists only per STT model (`MetricsStore.sttModelSummaries`), not for
  end-to-end perceived latency — add it alongside average/median/max when sample
  sizes are large enough to mean anything.
- Raw Dictation mode (skip AI reshaping) and any Pro/monetization features —
  explicitly deferred until after real-user validation; do not build speculatively.

**Recommended roadmap (agreed after multi-perspective review, see chat history
for the full reasoning — condensed here):**
1. ✅ **CLOSED (v1.6.4).** STT model comparison, 45 clips across two rounds.
   Settled: default `gpt-4o-mini-transcribe`, **full prose vocabulary prompt**,
   speech-rate guard. Both alternatives were tested and rejected on evidence —
   no prompt (short words collapse into other languages) and short prompt (echo
   survives but slips under the guard). Do not reopen without new evidence; the
   reasoning is in the v1.6.2–v1.6.4 notes above.
2. **← CURRENT STEP.** One week / ~200 real dictations of actual daily use (not
   lab sentences) with the chosen model. Tooling is ready: turn on Settings →
   Diagnostics → "Log statistics to disk" and leave the other two diagnostic
   switches **off** (compare mode costs 6× STT; capture-test-text holds dictated
   content). Then read the CSV, not impressions: run count, blocked count and
   their reasons, median and P95, and — the question the whole guard stack exists
   for — whether any row shows a hallucination that got inserted.
3. ✅ **Done.** v1.6.6 stayed frozen through the validation week; no features
   landed until it passed.
4. Three parts, in this order, after an independent review agreed the sequence:
   a. **Deliberately paused, by user decision (2026-08-14), not forgotten.**
      Staying on the current build for at least another week of ordinary daily
      use before spending the $99/yr or the setup time. Revisit after that week
      — do not start registration proactively before the user raises it again.
   b. ✅ **CLOSED (still on v1.6.10, no version bump needed — result is "don't
      switch").** Cleanup-model comparison, C1 test round, 60 phrases across 4
      groups (A short/everyday, B numbers/dates/addresses, C English terms in
      Lithuanian sentences, D long sentences + 5 decisive command-phrased
      sentences), `captureTestText` + `compareAICleanup` on.
      **Verdict: keep `claude-opus-4-8`. Do not switch to Haiku.** Rejected on
      quality, not close: the tool's own `would-be-rejected` flag fired on
      **14/60 runs (23%)** for Haiku vs **0/60** for Opus, concentrated exactly
      where it matters most — **5/5 (100%)** of Group D's decisive
      command-phrased sentences ("Parašyk kolegai...", "Sukurk laišką...",
      "Išversk šitą sakinį...", "Padaryk santrauką...", "Atsakyk į šį
      klausimą..."). On every one, Haiku didn't paste the dictated sentence back
      — it broke character and returned an English paragraph claiming it "only
      processes English dictated content" or refusing to act on an
      "instruction," even though the system prompt never restricts it to
      English. That paragraph would have landed in the user's document in place
      of their sentence. Opus passed all five as instructed: sentence preserved,
      grammar cleaned, nothing executed.
      Also found **silent regressions the automated flag missed** — same-length
      text that reads clean to the heuristic but changed something real:
      Haiku twice reformatted spoken numbers into digits ("keturi tūkstančiai
      septyni šimtai dvidešimt trys" → "4723"; a phone number the same way) —
      a reformat, which the mode's own contract forbids, even though nothing
      "grew"; twice it changed verb mood/tense ("prisijungt" → "prisijungti"
      instead of "prisijunk"; "Paleidžiu" → "Paleičiau"); three times it left
      an obvious STT error uncorrected that Opus caught and fixed
      ("neradinai spaudžia" → should be "terminai spaudžia", "Rytuoj" →
      "Rytoj", "persudėtingas" → "per sudėtingas"). None of these tripped
      `would-be-rejected` because line-break-count and length-ratio don't see
      word substitution — **a known blind spot of the comparison heuristic
      itself**, worth remembering if this tool is reused for a future model
      swap.
      Speed did not compensate and was not even consistently better: Haiku's
      median was faster in every group (0.85–1.15 s vs Opus's 1.23–1.59 s), but
      **P95 was worse than Opus in 2 of 4 groups** (Group A: 6.37 s vs 2.03 s;
      Group C: 2.74 s vs 2.50 s) — the refusal paragraphs are long, so the
      failure mode inflates the tail it was supposed to shrink.
      Per the pre-declared decision rule ("speed does not win against a meaning
      error"): stay on Opus, go straight to 4c when 4a resumes. Do not reopen
      this without a new model generation to test — the failure mode here is
      behavioral (Haiku mischaracterizing its own scope), not a prompt wording
      issue worth iterating on.
   c. Developer ID signing, hardened runtime, `notarytool` + `stapler`, and a
      clean-install check on **both** macOS 12 and 15, plus an update check that
      permissions and Keychain keys survive. **Blocked on 4a resuming.**
   Also before the pilot: walk the whole first-run path as a non-developer would
   — mic permission, Accessibility, both API keys present and valid, a
   comprehensible message for credit/rate-limit errors, a test dictation that
   proves the level meter moves and text lands, plain privacy wording (audio goes
   to OpenAI, transcript goes to Anthropic, the usage log is opt-in and holds no
   text or audio), and a Copy Diagnostics path a tester can use without Terminal.
5. Closed pilot with 5-10 Lithuanian-dictating Mac users (mixed technical
   skill, mixed hardware). The real signal is not feature requests — it's
   whether they keep opening the app unprompted after the novelty wears off.

   **Distribution is set up (2026-08-14); recruitment is the open half.**
   - Repo went **private** and `LICENSE` went **MIT → proprietary**. Both were
     live problems, not tidiness: the source *and* the Releases page were
     world-readable, and MIT expressly grants "distribute, sublicense, and/or
     sell". The swap binds going forward only — it cannot revoke rights for
     anyone who cloned while it was public.
   - The handout procedure — kept out of the public repo — is: send the terms,
     **wait for an explicit "I agree" reply**, then stamp that copy with the
     tester's name and send it directly. 30-day pilot window.
   - ⚠️ **BYO API keys are not a usage control.** They protect the OpenAI /
     Anthropic bill and nothing else — anyone holding the `.app` enters their
     own keys and it runs. This was briefly written down as a protection and it
     was wrong. What the pilot actually leans on is the private repo, the
     licence, the consent reply and the stamped name.
   - A full licence/activation backend is **deliberately not built**. For 5-10
     known people it is disproportionate, and it would not hide the prompts or
     the VAD from anyone determined to read the binary. Revisit before a 50-100
     person beta or anything paid.

   **Recruitment, as of 2026-08-19.** Contacts and the reasoning behind them are
   in Memora (`d2226a9e0b39`), not here, since they are people rather than code.
   The parts that bear on the product:
   - An outside reader was approached and, without ever installing it, found
     both hotkey defects behind v1.6.12-v1.6.14. Worth remembering as evidence
     for how cheap outside eyes are compared with another self-test round.
   - **Do not aim the first pilot at lawyers or doctors.** SEMANTIKA.LT / VDU
     already ships a Lithuanian transcriber with dedicated legal and medical
     modules, ~800 uses/day, deployed at LRT. It is a different category —
     audio *files* in, text out, not live dictation into the focused app — so
     it is not a competitor for this product, but it does own those verticals.
   - The gap this product sits in is real and confirmed: **Apple still does not
     support Lithuanian dictation**, ten years after MacArena wrote that it
     would not come soon.
6. Only after pilot feedback: Raw Dictation mode, faster/cheaper models for
   simple modes, and any Pro/paid tier — let real usage patterns decide what's
   actually worth building, not speculation.

**If you're a fresh session:** read this section, then check `git log --oneline
-20` and the latest `git tag` to see exactly what's shipped vs. still open
before writing any code.

---

## 11. Limits & tunables (dictation length)

There is **no hard recording time cap** — `AudioSessionManager` accumulates samples
in memory (~1.9 MB/min as a 16 kHz mono 16-bit WAV) and stops on VAD silence
(~1.2 s) or a second ⌥Space. The binding constraints are:

| Limit | Value | Where to change |
|---|---|---|
| VAD silence auto-stop | 1.2 s | `VoiceActivityDetector` (`silenceDuration`) |
| Transcription request timeout | **120 s** | `CloudWhisperService.init` (`timeoutIntervalForResource`) |
| OpenAI Whisper file cap | 25 MB ≈ ~13 min audio | OpenAI API (hard) |
| Claude reshape output cap | **8192 tokens** (~5000 words) | `ClaudeService.init` (`maxTokens`) |
| Claude request timeout | **60 s** | `ClaudeService.init` |

Practical guidance for users: dictate in sentences/paragraphs (pause < 2 s to keep
going). A single dictation is reliable up to a few minutes; beyond that the
transcription request approaches the 120 s timeout and the reshaped output may hit
the 8192-token cap. Raise the two timeouts + `maxTokens` if longer single takes are
needed.
```
