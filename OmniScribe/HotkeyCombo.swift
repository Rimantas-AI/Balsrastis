import AppKit

/// The global shortcut that starts and stops dictation, recorded from the user's
/// own keypress.
///
/// This replaced a fixed list of suggested combinations, which was wrong twice
/// within a day of shipping: ⌥Space is what a fair number of Mac users press to
/// switch input sources, and ⌘⇧D is **Send** in Apple Mail — an app dictation is
/// specifically meant to be used inside. One reader found both.
///
/// That is the whole argument against a list. Which combinations are free depends
/// on the apps a particular person runs, which is not knowable from here, so
/// anything shipped as "usually free" is a guess wearing a fact's clothing. Only
/// two claims survive in this file, and both were verified by report: ⌥Space
/// collides with input-source switching, and F13 is absent from MacBook
/// keyboards.
///
/// The event tap **consumes** whatever this is set to, system-wide, so the
/// combination is taken away from every other app. That is unavoidable for a
/// global shortcut; being able to move it is the mitigation.
struct HotkeyCombo: Equatable, Codable {

    /// Layout-independent virtual key code (`kVK_*`) — the code for the physical
    /// D key is 2 whether the layout is Lithuanian or US.
    let keyCode: Int64

    /// `CGEventFlags.rawValue`, already reduced to `relevantModifiers`.
    let modifierBits: UInt64

    /// Rendered once, at record time, from the key the user actually pressed.
    /// Storing it avoids maintaining a key-code-to-character table for every
    /// keyboard layout — the keypress itself already answered that question.
    let displayName: String

    var modifiers: CGEventFlags { CGEventFlags(rawValue: modifierBits) }

    /// Only these four are compared, so Caps Lock, fn and the numeric-pad flag
    /// can never prevent a match — `CGEventFlags` carries several bits that have
    /// nothing to do with the shortcut being pressed.
    static let relevantModifiers: CGEventFlags =
        [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    /// Matched **exactly**: ⌥Space must not fire when ⌘⌥Space is pressed, or the
    /// app would eat a shortcut it was never asked for.
    func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        keyCode == self.keyCode
            && flags.intersection(Self.relevantModifiers) == modifiers
    }

    /// Unchanged from the original hardcoded shortcut, so an existing install
    /// behaves as before until the user deliberately moves it.
    ///
    /// Kept as the default despite the known input-source collision: changing it
    /// would silently move the shortcut under people already used to this one,
    /// which is a second surprise rather than a fix. The recorder is the fix.
    static let `default` = HotkeyCombo(keyCode: 49,
                                       modifierBits: CGEventFlags.maskAlternate.rawValue,
                                       displayName: "\u{2325}Space")

    // MARK: – Recording

    /// Builds a combo from a recorded `NSEvent`, or `nil` if it would not be
    /// usable as a global shortcut.
    ///
    /// Requires ⌘, ⌥ or ⌃ unless the key is a function key. Shift alone does not
    /// count: ⇧A is how you type a capital A, so binding it would fire the
    /// recogniser mid-sentence, every sentence.
    init?(event: NSEvent) {
        let flags = Self.flags(from: event.modifierFlags)
        let code = Int64(event.keyCode)

        let hasRealModifier = !flags.intersection([.maskCommand, .maskAlternate, .maskControl]).isEmpty
        guard hasRealModifier || Self.functionKeyNames[code] != nil else { return nil }

        self.keyCode = code
        self.modifierBits = flags.rawValue
        self.displayName = Self.describe(keyCode: code, flags: flags, event: event)
    }

    init(keyCode: Int64, modifierBits: UInt64, displayName: String) {
        self.keyCode = keyCode
        self.modifierBits = modifierBits
        self.displayName = displayName
    }

    /// `NSEvent.ModifierFlags` → `CGEventFlags`, reduced to the four that matter.
    static func flags(from modifierFlags: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifierFlags.contains(.command)  { flags.insert(.maskCommand) }
        if modifierFlags.contains(.option)   { flags.insert(.maskAlternate) }
        if modifierFlags.contains(.control)  { flags.insert(.maskControl) }
        if modifierFlags.contains(.shift)    { flags.insert(.maskShift) }
        return flags
    }

    // MARK: – Display

    private static func describe(keyCode: Int64, flags: CGEventFlags, event: NSEvent) -> String {
        // Apple's canonical modifier order, so the result reads like every other
        // shortcut the user sees in a menu.
        var text = ""
        if flags.contains(.maskControl)   { text += "\u{2303}" }
        if flags.contains(.maskAlternate) { text += "\u{2325}" }
        if flags.contains(.maskShift)     { text += "\u{21E7}" }
        if flags.contains(.maskCommand)   { text += "\u{2318}" }
        return text + keyName(keyCode: keyCode, event: event)
    }

    /// Named keys whose typed character is blank or unreadable. Everything else
    /// falls back to the character the key produces, which handles every layout
    /// without a table.
    private static let namedKeys: [Int64: String] = [
        49: "Space", 36: "Return", 48: "Tab", 53: "Escape", 51: "Delete",
        117: "Fwd Delete", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        123: "\u{2190}", 124: "\u{2192}", 125: "\u{2193}", 126: "\u{2191}",
    ]

    private static let functionKeyNames: [Int64: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
        80: "F19", 90: "F20",
    ]

    private static func keyName(keyCode: Int64, event: NSEvent) -> String {
        if let named = functionKeyNames[keyCode] { return named }
        if let named = namedKeys[keyCode] { return named }
        let typed = (event.charactersIgnoringModifiers ?? "").uppercased()
        return typed.isEmpty ? "Key \(keyCode)" : typed
    }

    // MARK: – What already owns a combination

    private struct Reservation {
        let keyCode: Int64
        let modifiers: CGEventFlags
        let owner: String
    }

    /// Combinations with a **documented** owner: an Apple default, or a conflict
    /// someone reported from real use.
    ///
    /// The bar for being in this list is deliberately high, because the previous
    /// version of this file shipped a table of combinations labelled "usually
    /// free" that were never checked — two of the five were wrong. So: an entry
    /// here means it is documented or was reported. An *absent* combination
    /// means "nothing known about it", which is not the same as "free", and the
    /// UI must not imply otherwise.
    private static let reservations: [Reservation] = [
        // Input sources — the pair this whole thread started from. Note it is
        // ⌃Space, not ⌥Space, that macOS ships as the language switcher.
        .init(keyCode: 49, modifiers: [.maskControl],
              owner: "macOS: select the previous input source"),
        .init(keyCode: 49, modifiers: [.maskControl, .maskAlternate],
              owner: "macOS: select the next input source"),

        // Spotlight and Finder search.
        .init(keyCode: 49, modifiers: [.maskCommand],
              owner: "macOS: Spotlight search"),
        .init(keyCode: 49, modifiers: [.maskCommand, .maskAlternate],
              owner: "macOS: Finder search window"),

        // Apple's own Dictation on 2021+ MacBooks with a microphone key.
        .init(keyCode: 96, modifiers: [],
              owner: "Apple Dictation on MacBooks with a microphone key"),

        // App switcher and Spaces.
        .init(keyCode: 48, modifiers: [.maskCommand],
              owner: "macOS: switch applications"),
        .init(keyCode: 123, modifiers: [.maskControl],
              owner: "macOS: move one space left"),
        .init(keyCode: 124, modifiers: [.maskControl],
              owner: "macOS: move one space right"),
        .init(keyCode: 126, modifiers: [.maskControl],
              owner: "macOS: Mission Control"),
        .init(keyCode: 125, modifiers: [.maskControl],
              owner: "macOS: application windows"),

        // Screenshots.
        .init(keyCode: 20, modifiers: [.maskCommand, .maskShift],
              owner: "macOS: screenshot the whole screen"),
        .init(keyCode: 21, modifiers: [.maskCommand, .maskShift],
              owner: "macOS: screenshot a selection"),
        .init(keyCode: 23, modifiers: [.maskCommand, .maskShift],
              owner: "macOS: screenshot and recording options"),

        // Reported from real use rather than documented by Apple: this one cost
        // a release. Dictating into mail is a main use of this app, so losing
        // Send to the dictation shortcut is not a small collision.
        .init(keyCode: 2, modifiers: [.maskCommand, .maskShift],
              owner: "Apple Mail: Send"),
    ]

    /// Set when something documented already claims this combination.
    var reservedBy: String? {
        Self.reservations.first { $0.keyCode == keyCode && $0.modifiers == modifiers }?.owner
    }

    /// The note worth showing about the current shortcut, strongest first.
    /// `nil` means nothing is known about it — **not** that it is free.
    var advisory: String? {
        if let owner = reservedBy {
            return "Already used by \u{2014} \(owner). Dictation will win, and that stops working."
        }
        if self == Self.default {
            return "Some people remap \u{2325}Space to switch input sources. If you did, record a different one."
        }
        if Self.functionKeyNames[keyCode] != nil, modifiers.isEmpty, keyCode == 105 {
            return "MacBook keyboards have no F13 key."
        }
        return nil
    }
}
