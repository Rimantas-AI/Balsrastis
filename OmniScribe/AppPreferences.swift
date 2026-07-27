import Foundation
import Combine

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

    /// `gpt-4o-transcribe`/`-mini` are OpenAI's newer transcription models,
    /// reported to improve word-error-rate and language recognition over the
    /// original Whisper models — worth comparing directly on Lithuanian speech
    /// rather than assuming the newer model wins for this specific language.
    static let availableSTTModels = ["whisper-1", "gpt-4o-mini-transcribe", "gpt-4o-transcribe"]
    static let defaultSTTModel = "whisper-1"

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

        selectedProvider = AILayerCoordinator.shared.selectedProvider
    }
}
