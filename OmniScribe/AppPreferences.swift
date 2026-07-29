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
    /// Dropping the prompt is settled as **not viable**: without it short
    /// Lithuanian words collapse into other languages ("Taip" came back as
    /// `طيب`, `Тайпа`, `ty`; "Ne" as `네`). The prompt is what holds the
    /// recogniser in Lithuanian on short audio. The no-prompt arm survives only
    /// as a diagnostic baseline — it is not a candidate configuration.
    ///
    /// A third, shortened prompt form was tested in v1.6.4 and **rejected**; see
    /// the v1.6.4 notes in AGENTS.md for the numbers. It is deliberately not
    /// present in this file: keeping a rejected prompt next to the live one
    /// invites a future reader to conclude the shorter one looks cleaner.
    enum Prompt: String, Hashable {
        /// The user's editable vocabulary from Settings (prose).
        case full
        /// No `prompt` parameter at all.
        case none

        var suffix: String {
            switch self {
            case .full: return " \u{00B7} full prompt"
            case .none: return " \u{00B7} no prompt"
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
        case .full: return fullVocabulary
        case .none: return ""
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
    private let logUsageStatisticsKey = "OmniScribe.logUsageStatistics"

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

    /// Appends one row per dictation to `UsageLog.fileURL`, surviving relaunches.
    ///
    /// Separate from `captureTestText` and deliberately so: that switch controls
    /// whether dictated *content* is held in memory, this one controls whether
    /// *statistics* are written to disk. Conflating them would mean a week-long
    /// measurement could not be run without also recording everything the user
    /// dictated. The log stores no text — see `UsageLog`.
    @Published var logUsageStatistics: Bool {
        didSet { defaults.set(logUsageStatistics, forKey: logUsageStatisticsKey) }
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

    /// The six comparison arms: every model, with and without the vocabulary
    /// prompt, on identical audio. Diagnostic only — the no-prompt arms are a
    /// baseline for reading the others, never a configuration to ship.
    static let comparisonVariants: [STTVariant] = availableSTTModels.flatMap { model in
        [STTVariant(model: model, prompt: .full),
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
        logUsageStatistics = defaults.bool(forKey: logUsageStatisticsKey)

        selectedProvider = AILayerCoordinator.shared.selectedProvider
    }
}
