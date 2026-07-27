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
    Tai lietuviška techninė diktacija apie macOS programą „OmniScribe". Galimi \
    terminai: HUD, Accessibility, Keychain, TextEdit, Diagnostics, build, GitHub, \
    Claude, Whisper, API, Settings, Always Allow.
    """

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

        selectedProvider = AILayerCoordinator.shared.selectedProvider
    }
}
