import AppKit

// MARK: – AppState

/// Represents the three visual states of the Menu Bar icon.
enum AppState: String {
    case idle       = "Idle"
    case listening  = "Listening"
    case processing = "Processing"

    /// SF Symbol name for each state.
    var symbolName: String {
        switch self {
        case .idle:       return "mic"
        case .listening:  return "mic.fill"
        case .processing: return "waveform"
        }
    }

    var tooltip: String { "Balsraštis – \(rawValue)" }
}

// MARK: – MenuBarManager

/// Owns the `NSStatusItem` and keeps its icon/menu in sync with `AppState`.
///
/// All public methods are safe to call from any thread – they dispatch to
/// the main queue internally.
final class MenuBarManager: NSObject, NSMenuDelegate {

    // MARK: Private state

    private let statusItem: NSStatusItem
    private let statusMenuItem = NSMenuItem()   // Shows "Balsraštis – <state>" as info row.
    private let hotkeyHintItem = NSMenuItem()   // Shows the currently chosen shortcut.
    private let dictateItem = NSMenuItem()      // Starts/stops dictation without the keyboard.

    /// Starts or stops dictation — the same action the shortcut triggers.
    ///
    /// Asked for by a reader who pointed out that a keyboard shortcut is the
    /// only way in, which is a problem for anyone whose preferred combination
    /// is taken and for anyone who simply reaches for the menu first.
    var onToggleDictation: (() -> Void)?

    private(set) var currentState: AppState = .idle {
        didSet { refreshButton() }
    }

    // MARK: Init

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        configureMenu()
    }

    // MARK: – NSMenuDelegate

    /// The shortcut is user-changeable, but the menu is built once at launch, so
    /// its hint is refreshed the moment before the menu is shown rather than
    /// when the preference changes — no subscription to keep in sync, and the
    /// text is correct whenever anyone can actually read it.
    func menuWillOpen(_ menu: NSMenu) {
        hotkeyHintItem.title = "Or press: \(AppPreferences.shared.hotkey.displayName)"
        // Labelled from the current state, so the menu is also how you find out
        // whether it is still listening.
        dictateItem.title = currentState == .idle ? "Start Dictation" : "Stop Dictation"
    }

    @objc private func toggleDictation() {
        onToggleDictation?()
    }

    // MARK: – Public API

    /// Updates the icon and status label. Thread-safe.
    func updateState(_ state: AppState) {
        DispatchQueue.main.async { [weak self] in
            self?.currentState = state
        }
    }

    // MARK: – Private – Button

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = makeIcon(for: .idle)
        button.toolTip = AppState.idle.tooltip
    }

    private func refreshButton() {
        guard let button = statusItem.button else { return }
        button.image = makeIcon(for: currentState)
        button.toolTip = currentState.tooltip
        statusMenuItem.title = "Balsraštis – \(currentState.rawValue)"
    }

    private func makeIcon(for state: AppState) -> NSImage? {
        let img = NSImage(systemSymbolName: state.symbolName,
                          accessibilityDescription: state.tooltip)
        img?.isTemplate = true  // Automatically adapts to dark/light Menu Bar.
        return img
    }

    // MARK: – Private – Menu

    private func configureMenu() {
        let menu = NSMenu()

        // --- Info row (disabled, shows current state) ---
        statusMenuItem.title = "Balsraštis – Idle"
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        // --- Start / stop dictation ---
        dictateItem.title = "Start Dictation"
        dictateItem.action = #selector(toggleDictation)
        dictateItem.target = self
        menu.addItem(dictateItem)

        // --- Hotkey hint ---
        // Title is set here and refreshed in `menuWillOpen`, so it follows the
        // user's choice instead of permanently claiming ⌥Space.
        hotkeyHintItem.title = "Activate: \(AppPreferences.shared.hotkey.displayName)"
        hotkeyHintItem.isEnabled = false
        menu.addItem(hotkeyHintItem)

        menu.addItem(.separator())

        // --- Settings ---
        let settingsItem = NSMenuItem(title: "Settings\u{2026}",
                                      action: #selector(openSettings),
                                      keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // --- Quit ---
        let quitItem = NSMenuItem(title: "Quit Balsraštis",
                                  action: #selector(quitApp),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: – Actions

    @objc private func openSettings() {
        WindowManager.shared.showSettings()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
