# OmniScribe — Agent / LLM Handoff Guide

> Read this fully before changing anything. It captures **what the app is, how it
> works, why each key decision was made, and the traps that already cost days.**
> Written for another AI agent (or developer) picking up the project cold.

Repo: `https://github.com/g4me2011-lang/omniScribe`

---

## 1. What OmniScribe is

A **menu-bar-only macOS app** for voice dictation with AI post-processing. The user
presses a global hotkey (**⌥Space / Option+Space**), speaks, and cleaned-up text is
**pasted into whatever app currently has focus** (TextEdit, Mail, Slack, browser,
this chat box — anything).

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
  → VoiceActivityDetector                 auto-stop after ~2 s of silence …
      OR ⌥Space again                     … or manual stop
  → AudioSessionManager.stop() → [Float]  the captured samples
  → CloudWhisperService.transcribe()      OpenAI Whisper API → Lithuanian text
  → AILayerCoordinator.process(text,mode) Claude (Anthropic) reshapes per mode
  → TextInjector.inject(processed)         save clipboard → set text → ⌘V → restore clipboard
  → back to idle, HUD hidden
```

States are shown via the menu-bar icon (`MenuBarManager`: idle / listening /
processing) and a floating panel (`WindowManager` + `HUDPanel` + `RecordingHUDView`).

All errors in the async pipeline are `catch`-ed and `print`-ed with an ❌ prefix; they
are **not** surfaced in the UI yet. To debug, run from Terminal and watch stdout
(see §7).

---

## 3. File / module map (21 Swift files)

**AppCore / lifecycle**
- `OmniScribeApp.swift` — `@main`, `Settings { EmptyView() }`, no `WindowGroup`.
- `AppDelegate.swift` — owns all services; orchestrates the dictation cycle. **Start here.**
- `MenuBarManager.swift` — `NSStatusItem`, 3-state icon, menu (Settings / Quit).
- `PermissionManager.swift` — requests Microphone + Accessibility, shows NSAlerts.
- `AppPreferences.swift` — `ObservableObject`, persists `selectedMode` + `selectedProvider` (UserDefaults; **not** secrets).

**Hotkey / OS interop**
- `HotkeyManager.swift` — global **CGEventTap** for ⌥Space; **requires Accessibility**; guards with `AXIsProcessTrusted()`. Takes an `onTrigger` closure.
- `TextInjector.swift` — `@MainActor`; clipboard-save → set string → synthesize ⌘V via `CGEvent` (`.cghidEventTap`) → `Task.sleep(120 ms)` → clipboard-restore. Requires Accessibility.
- `ClipboardState.swift` — deep-copies `NSPasteboardItem`s so text/image/file clipboard survives.

**Audio**
- `AudioSessionManager.swift` — `AVAudioEngine`, taps input, converts to 16 kHz mono Float32, feeds VAD; handles device changes; removes tap **before** stopping engine.
- `VoiceActivityDetector.swift` — RMS-based; only counts silence **after** it has first detected speech above threshold (0.012). Fires `onSilenceTimeout` once after ~2 s silence.
- `STTResult.swift` — provider-agnostic result `{ text, language, audioDuration, source }`.

**STT (speech → text)**
- `CloudWhisperService.swift` — **THE ACTIVE TRANSCRIBER.** Uploads a 16 kHz mono WAV to the **OpenAI Whisper API** (`/v1/audio/transcriptions`, `language=lt`). Needs the **OpenAI** Keychain key.
- `LocalTranscriptionService.swift` — Apple `SFSpeechRecognizer` path. **Currently NOT wired into AppDelegate** (leftover). Apple Speech does **not** support `lt-LT`, so it can't do Lithuanian. Keep for reference / future non-Lithuanian on-device use, or delete.

**AI reshaping (text → text)**
- `AIProviderProtocol.swift` — `AIProviderProtocol { process(text:mode:) }`, `AIProviderID { claude, gemini, openai }`, `AIError`.
- `ProcessingMode.swift` — enum `{ ltTyping, email, code, messenger, translation }`, each carries a system prompt. `.ltTyping` = grammar cleanup keeping original language.
- `ClaudeService.swift` — Anthropic Messages API via raw `URLSession` (no Swift SDK). Model `claude-opus-4-8`. **No** temperature/top_p (rejected on Opus 4.7/4.8). 10 s timeout. Needs the **Claude** Keychain key.
- `AILayerCoordinator.swift` — factory routing to the selected provider. **Only `ClaudeService` is registered**; Gemini/OpenAI-as-reshaper are not implemented.

**Security**
- `KeychainManager.swift` — generic-password CRUD keyed by provider `rawValue` under service `com.omniscribe.app.apikeys`. Keys **never** touch UserDefaults. **Per-machine** (keys do not travel with the app).

**UI**
- `SettingsView.swift` — native `TabView` (General + API Keys) + `Form` + `Picker`. No iOS `NavigationView`. General tab: mode + AI-provider pickers. API Keys tab: one `SecureField` per provider (Save/Remove), backed by Keychain.
- `RecordingHUDView.swift` — SwiftUI HUD content (listening/processing).
- `HUDPanel.swift` — non-activating `NSPanel`, `.floating` level, `ignoresMouseEvents`, `canBecomeKey = false` (must never steal focus).
- `WindowManager.swift` — presents the Settings window and the HUD panel safely for an `LSUIElement` app.

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

8. **App Sandbox is DISABLED** (`OmniScribe.entitlements`). CGEventTap + Accessibility + global paste can't work under the sandbox. Consequence: distribution is **Developer ID + notarization**, not the Mac App Store.

---

## 5. Build & distribution (no local Xcode — CI does it)

The user has **no full Xcode locally** (only Command Line Tools) and a modest Intel
Mac. All compiling happens on **GitHub Actions macOS runners**. Never assume a local
`xcodebuild`.

- Workflow: `.github/workflows/build.yml`. Trigger: push to `main` or manual dispatch.
- Runner `macos-15` + `maxim-lobanov/setup-xcode@v1 latest-stable` (a modern Xcode is required or SwiftPM resolution fails).
- Build command uses **`-scheme OmniScribe`** (a shared scheme exists at
  `OmniScribe.xcodeproj/xcshareddata/xcschemes/OmniScribe.xcscheme`). ⚠️ `-derivedDataPath`
  **requires** `-scheme`, not `-target` — this cost a failed build.
- `MACOSX_DEPLOYMENT_TARGET=14.0` was passed in CI while WhisperKit existed; the
  project target is now **12.0**. Keep CI override ≥ project target.
- Build is **unsigned** (`CODE_SIGNING_ALLOWED=NO`) then **ad-hoc signed**
  (`codesign --force --deep --sign -`) so it launches.
- Output: `OmniScribe.zip` uploaded as artifact **`OmniScribe-app`**. After WhisperKit
  removal the app is tiny (~0.3 MB) — models are not bundled; STT is cloud.

**To ship the built app to a user's Mac:** download the artifact (requires being
logged into GitHub), unzip twice → `OmniScribe.app`, then on the Mac:
`xattr -dr com.apple.quarantine /Applications/OmniScribe.app` (ad-hoc apps are
quarantine-blocked), then grant permissions.

**Verifying a CI run from a headless/agent context** (no `gh` auth): use the public
REST API, e.g.
`curl -s https://api.github.com/repos/g4me2011-lang/omniScribe/actions/runs`
and `.../runs/{id}/jobs` for step results. Logs need auth (403 unauthenticated).

---

## 6. Permissions the app needs (and the #1 gotcha)

| Permission | Why | Where |
|---|---|---|
| **Microphone** | capture audio | Privacy → Microphone |
| **Accessibility** | CGEventTap hotkey **and** synthetic ⌘V paste | Privacy → Accessibility |
| **Speech Recognition** | only if using the Apple `LocalTranscriptionService` path (not the active OpenAI path) | Privacy → Speech Recognition |

**Gotcha — running from Terminal attributes permissions to Terminal, not OmniScribe.**
When you launch `…/OmniScribe.app/Contents/MacOS/OmniScribe` from a terminal to see
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

- Run from Terminal to see logs: `/Applications/OmniScribe.app/Contents/MacOS/OmniScribe`
  (mind the permission gotcha above — grant the terminal Mic+Accessibility).
- Log prefixes to grep: `[HotkeyManager]`, `[AppDelegate]`, `[CloudWhisperService]`.
  Key lines: `✅ Global hotkey ⌥Space registered`, `⏹️ Recording stopped – N samples`,
  `📝 Transcription (...)`, `✨ Processed (...)`, `⌨️ Inserted`, `❌ Pipeline failed: …`.
- `"🎵🎵🎵"` transcription = **silence/no speech reached Whisper** (mic not capturing;
  see permission gotcha, wrong input device, or background music).
- No auto-stop after silence = VAD never saw speech = same root cause (silent audio),
  or genuine mic level below the 0.012 RMS threshold.
- Multiple menu-bar mic icons = multiple instances (each Terminal launch spawns one);
  `killall OmniScribe`. NOTE: an isolated agent shell may not see the user's GUI
  processes — have the **user** run `killall`.
- Crash reports: `~/Library/Logs/DiagnosticReports/OmniScribe*.ips` (JSON; parse the
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
  matter that were never spoken (one of them — "OmniScribe transkribuoja jūsų
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
4. **← CURRENT STEP.** Three parts, in this order, after an independent review
   agreed the sequence:
   a. **Start the Apple Developer registration now, in parallel.** It can take
      days and must not become the blocking wait.
   b. **Cleanup-model comparison (Opus vs Haiku) before notarizing.** AI cleanup
      is 44.3% of latency and `claude-opus-4-8` is very likely overpowered for
      fixing grammar. Test it the way the STT choice was tested: send the same
      `Raw STT` text to both models, log both, and **insert only the primary
      model's output** so daily use is untouched. Pin the dated id
      (`claude-haiku-4-5-20251001`), not the alias, so a rerun compares the same
      thing. Cheap to test, because here the input is *text*, not audio.
      Switch only if: no meaning or fact changes, no invented content, Lithuanian
      quality not materially worse, `AI cleanup rejected` stays at its current
      zero, and **P95 improves** — weight the tail over the median, since a 30%
      median gain on the AI stage is only ~12% end-to-end while the tail is what
      makes the app feel stuck.
      ⚠️ This round needs `captureTestText` on — judging cleanup quality requires
      seeing the text. That is what the switch is for; turn it off afterwards.
      Notarize the *chosen* configuration, so testers are not handed a build
      whose main model changes days later.
   c. Then Developer ID signing, hardened runtime, `notarytool` + `stapler`, and
      a clean-install check on **both** macOS 12 and 15, plus an update check
      that permissions and Keychain keys survive.
   Also before the pilot: walk the whole first-run path as a non-developer would
   — mic permission, Accessibility, both API keys present and valid, a
   comprehensible message for credit/rate-limit errors, a test dictation that
   proves the level meter moves and text lands, plain privacy wording (audio goes
   to OpenAI, transcript goes to Anthropic, the usage log is opt-in and holds no
   text or audio), and a Copy Diagnostics path a tester can use without Terminal.
5. Closed pilot with 5-10 Lithuanian-dictating Mac users (mixed technical
   skill, mixed hardware). The real signal is not feature requests — it's
   whether they keep opening the app unprompted after the novelty wears off.
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
(~2 s) or a second ⌥Space. The binding constraints are:

| Limit | Value | Where to change |
|---|---|---|
| VAD silence auto-stop | ~2 s | `VoiceActivityDetector` (`silenceDuration`) |
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
