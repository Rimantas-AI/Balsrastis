import Foundation
import Combine

/// One arm of the same-audio comparison: a transcription model plus whether the
/// vocabulary prompt is sent with it.
///
/// The prompt is part of the comparison rather than a fixed setting because the
/// models interpret it in fundamentally different ways. Measured: given the
/// standard Lithuanian vocabulary prompt, `gpt-4o-mini-transcribe` returned that
/// prompt back *verbatim* instead of a transcript, and `gpt-4o-transcribe`
/// answered with sentences built from the prompt's subject matter that were never
/// spoken. `whisper-1` transcribed the same audio correctly. Whisper treats
/// `prompt` as a spelling/style bias; the gpt-4o models treat it much more like
/// context given to a language model.
///
/// Testing prompt on/off also answers a question that matters beyond model
/// choice: the vocabulary prompt is what supplies the content of the
/// keyboard-noise hallucination, so a model that handles jargon well *without*
/// it would let that prompt be dropped entirely.
struct STTVariant: Hashable {
    /// Which vocabulary hint accompanies the audio.
    ///
    /// Three kinds rather than on/off, because the 30-clip round closed the
    /// on/off question and opened a sharper one. Dropping the prompt entirely is
    /// not viable — without it short Lithuanian words collapsed into other
    /// languages ("Taip" came back as `طيب`, `Тайпа`, `ty`; "Ne" as `네`) — so
    /// the prompt is what holds the recogniser in Lithuanian on short audio.
    /// But the *full* prompt is written as prose, and complete sentences are
    /// exactly what a model can echo back when it has only noise to work with.
    /// A short term list may keep the language anchor without supplying that
    /// material.
    ///
    /// ⚠️ This is a hypothesis, not a conclusion. A bare comma list was already
    /// tried for `whisper-1` back in v1.3.x and **barely helped** — the sentence
    /// form is what worked. That was measured on whisper only, so it may not
    /// carry over to the gpt-4o models, but it is the reason the short prompt is
    /// being *tested* rather than simply adopted.
    enum Prompt: String, Hashable {
        /// The user's editable vocabulary from Settings (currently prose).
        case full
        /// A short, non-narrative term list — see `AppPreferences.shortVocabulary`.
        case short
        /// No `prompt` parameter at all.
        case none

        var suffix: String {
            switch self {
            case .full:  return " \u{00B7} full prompt"
            case .short: return " \u{00B7} short prompt"
            case .none:  return " \u{00B7} no prompt"
            }
        }
    }

    let model: String
    let prompt: Prompt

    /// Display/grouping key. Also the value stored in
    /// `STTComparisonResult.model`, so results group per variant, not per model.
    var label: String { model + prompt.suffix }

    /// The text to send as this arm's `prompt`, given the user's current
    /// vocabulary setting.
    func promptText(fullVocabulary: String) -> String {
        switch prompt {
        case .full:  return fullVocabulary
        case .short: return AppPreferences.shortVocabulary
        case .none:  return ""
        }
    }
}

/// Shared, observable app preferences bound by the Settings UI and read by the
/// dictation pipeline. Holds only non-secret choices — the active mode and the
/// selected provider. **API keys are never stored here**; they live exclusively
/// in `KeychainManager`.
final class AppPreferences: ObservableObject {

    static let shared = AppPreferences()

    private let defaults: UserDefaults
    private let modeKey = "OmniScribe.selectedMode"
    private let vocabularyKey = "OmniScribe.vocabulary"
    private let captureTestTextKey = "OmniScribe.captureTestText"
    private let sttModelKey = "OmniScribe.sttModel"
    private let compareSTTModelsKey = "OmniScribe.compareSTTModels"

    /// Context the speech recogniser should expect.
    ///
    /// Sent to Whisper as its `prompt`, which biases recognition toward this
    /// context. Without it, English technical terms spoken inside Lithuanian
    /// sentences come back phonetically mangled ("HUD" → "gūdą"), and no amount of
    /// LLM cleanup can recover them — the word is already gone by then.
    ///
    /// Phrased as a short Lithuanian sentence rather than a bare comma list:
    /// OpenAI's own guidance describes `prompt` as context that steers spelling
    /// and style, not a strict dictionary, and it should match the spoken
    /// language — a plain English word list nudges the recogniser off-language.
    @Published var vocabulary: String {
        didSet { defaults.set(vocabulary, forKey: vocabularyKey) }
    }

    static let defaultVocabulary = """
    Tai lietuviška techninė diktacija apie macOS programą „OmniScribe". Programos \
    HUD, tariama raidėmis H-U-D, rodo būsenas „Listening", „Transcribing" ir \
    „Polishing". Nustatymuose yra skiltys „API Keys" ir „Diagnostics", o ten \
    mygtukai „Copy Report" ir „Clear Diagnostics". Galimi terminai: Mac \
    slaptažodis, API raktas, Keychain, Always Allow, TextEdit, Accessibility, \
    GitHub, Claude, Whisper. Klaidos pranešimas gali būti „No microphone signal".
    """

    /// Whether the raw Whisper transcript and AI-reshaped result are captured
    /// into Diagnostics history at all (see `DictationMetrics.transcribedText` /
    /// `.processedText`). Off by default: normal daily use has no reason to hold
    /// dictated content in memory, even transiently — this should only be
    /// switched on for a deliberate STT/vocabulary test round, then off again.
    @Published var captureTestText: Bool {
        didSet { defaults.set(captureTestText, forKey: captureTestTextKey) }
    }

    /// Which OpenAI transcription model to send audio to. Switchable at runtime
    /// (no relaunch) so the same test script can be re-run per model and compared
    /// via Diagnostics' `Raw STT` field and per-run `sttModel` label.
    @Published var sttModel: String {
        didSet { defaults.set(sttModel, forKey: sttModelKey) }
    }

    /// Sends every recording to **all** of `availableSTTModels` concurrently, so
    /// the models can be compared on identical audio. Re-recording the same
    /// phrase per model is not a valid comparison — pronunciation, pace and mic
    /// distance differ between takes and confound the result.
    ///
    /// Diagnostic only, off by default: it roughly triples STT API usage, and the
    /// extra calls are pure cost outside a deliberate test round. The insert path
    /// is unaffected — only `sttModel`'s result is reshaped and pasted.
    @Published var compareSTTModels: Bool {
        didSet { defaults.set(compareSTTModels, forKey: compareSTTModelsKey) }
    }

    /// `gpt-4o-transcribe`/`-mini` are OpenAI's newer transcription models,
    /// reported to improve word-error-rate and language recognition over the
    /// original Whisper models — worth comparing directly on Lithuanian speech
    /// rather than assuming the newer model wins for this specific language.
    static let availableSTTModels = ["gpt-4o-mini-transcribe", "whisper-1", "gpt-4o-transcribe"]

    /// Chosen from the 30-clip round, not from reputation: `gpt-4o-mini-transcribe`
    /// was the most accurate on long Lithuanian sentences (whisper-1 dropped a
    /// negation and inverted a sentence's meaning), the only one besides
    /// gpt-4o-transcribe to survive background music, and the fastest with the
    /// tightest tail — median 0.72s, P95 1.19s, slowest 1.19s, against whisper-1's
    /// 1.09 / 1.66 / **6.48s**.
    ///
    /// Existing installs keep whatever is in `UserDefaults`; this only affects a
    /// fresh install. Switch in Settings → General.
    static let defaultSTTModel = "gpt-4o-mini-transcribe"

    /// How each model is meant to be used, shown in the picker so the choice is
    /// not just three opaque identifiers.
    static func roleDescription(for model: String) -> String {
        switch model {
        case "gpt-4o-mini-transcribe": return "\(model) — recommended"
        case "whisper-1":              return "\(model) — reliable fallback"
        case "gpt-4o-transcribe":      return "\(model) — experimental"
        default:                       return model
        }
    }

    /// Every arm of the comparison: each model with and without the vocabulary
    /// prompt. The no-prompt half exists because the gpt-4o models proved unusable
    /// *with* our prompt (see `STTVariant`) — without testing them without it,
    /// the comparison would reject them for a reason that may be entirely fixable.
    /// whisper-1 is included in the no-prompt half too, to re-check the earlier
    /// finding that the prompt helps it rather than assuming it still holds.
    /// ⚠️ **Tested and rejected. Do not adopt this as the default prompt.**
    ///
    /// The idea was sound — the full prompt is prose, and whole sentences are
    /// what a model echoes back from noise, so a bare term list should keep the
    /// language anchor without supplying recitable material. It half worked:
    /// short words stayed accurate (`Taip` 4/4, `Ne` 5/5).
    ///
    /// It failed on the part that mattered, in a way worth remembering: **the
    /// echo did not stop, it merely got shorter** — and short enough to slip
    /// under `exceedsPlausibleSpeechRate`. On identical keyboard noise the full
    /// prompt came back at ~10.2 words/second (blocked), the short one at ~2.77
    /// (would have been pasted). `whisper-1` with this prompt answered the same
    /// noise with `[www.omniScribe.com](...)`, three times, which would also have
    /// been pasted.
    ///
    /// So shortening the prompt would have *removed the very signal the guard
    /// relies on*. The full prompt is accidentally safer for being long. Kept
    /// here only as the record of a measured negative result.
    static let shortVocabulary = """
    Lietuvių kalba. Terminai: OmniScribe, HUD, Settings, API Keys, Diagnostics, \
    Keychain, Copy Report, Clear Diagnostics, Accessibility, GitHub, Claude, Whisper.
    """

    /// The six comparison arms: the two viable models against all three prompt
    /// forms.
    ///
    /// `gpt-4o-transcribe` was dropped from the comparison after the 30-clip
    /// round — it hallucinated fluent text from keyboard noise *even with no
    /// prompt at all* ("How are you doing?"), and turned short Lithuanian words
    /// into Arabic, Korean and Cyrillic script. Its larger size bought nothing
    /// over the mini model here. Re-add it if there is ever a reason to revisit;
    /// the six slots are better spent on the open question, which is prompt form.
    static let comparisonVariants: [STTVariant] = ["gpt-4o-mini-transcribe", "whisper-1"]
        .flatMap { model in
            [STTVariant(model: model, prompt: .full),
             STTVariant(model: model, prompt: .short),
             STTVariant(model: model, prompt: .none)]
        }

    /// The processing mode applied after transcription. Persisted so it survives
    /// relaunch. `didSet` writes through to `UserDefaults`.
    @Published var selectedMode: ProcessingMode {
        didSet { defaults.set(selectedMode.rawValue, forKey: modeKey) }
    }

    /// The active AI provider. Bridged to `AILayerCoordinator`, which is the
    /// source of truth for the persisted value (keeps a single writer).
    @Published var selectedProvider: AIProviderID {
        didSet { AILayerCoordinator.shared.selectedProvider = selectedProvider }
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let raw = defaults.string(forKey: modeKey),
           let mode = ProcessingMode(rawValue: raw) {
            selectedMode = mode
        } else {
            selectedMode = .ltTyping
        }

        vocabulary = defaults.string(forKey: vocabularyKey) ?? Self.defaultVocabulary
        captureTestText = defaults.bool(forKey: captureTestTextKey)
        sttModel = defaults.string(forKey: sttModelKey) ?? Self.defaultSTTModel
        compareSTTModels = defaults.bool(forKey: compareSTTModelsKey)

        selectedProvider = AILayerCoordinator.shared.selectedProvider
    }
}
