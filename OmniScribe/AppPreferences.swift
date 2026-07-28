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
    let model: String
    let useVocabulary: Bool

    /// Display/grouping key. Also the value stored in
    /// `STTComparisonResult.model`, so results group per variant, not per model.
    var label: String { useVocabulary ? model : "\(model) \u{00B7} no prompt" }
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
    static let availableSTTModels = ["whisper-1", "gpt-4o-mini-transcribe", "gpt-4o-transcribe"]
    static let defaultSTTModel = "whisper-1"

    /// Every arm of the comparison: each model with and without the vocabulary
    /// prompt. The no-prompt half exists because the gpt-4o models proved unusable
    /// *with* our prompt (see `STTVariant`) — without testing them without it,
    /// the comparison would reject them for a reason that may be entirely fixable.
    /// whisper-1 is included in the no-prompt half too, to re-check the earlier
    /// finding that the prompt helps it rather than assuming it still holds.
    static let comparisonVariants: [STTVariant] = availableSTTModels.flatMap { model in
        [STTVariant(model: model, useVocabulary: true),
         STTVariant(model: model, useVocabulary: false)]
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
