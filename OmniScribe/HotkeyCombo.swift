import AppKit

/// The global shortcut that starts and stops dictation, chosen from a fixed list.
///
/// A fixed list rather than a free-form recorder: a recorder has to cope with
/// dead keys, layout-dependent key codes and shortcuts the system already owns,
/// and none of that is the problem being solved. The problem is narrow and came
/// from real use — ⌥Space was hardcoded *and consumed* (`HotkeyManager` returns
/// `nil` so the focused app never sees it), so for anyone who uses ⌥Space to
/// switch input sources, installing OmniScribe silently broke their language
/// switching with no way to change it. That lands hardest on exactly this app's
/// users, who alternate between Lithuanian and English layouts all day.
///
/// Every option here collides with *something* somewhere — that is unavoidable
/// for a shortcut consumed system-wide. The point is that the user can move it,
/// not that a perfect default exists; hence `conflictNote`, so a collision is a
/// choice made in advance rather than a surprise found later.
enum HotkeyCombo: String, CaseIterable, Identifiable {
    case optionSpace
    case commandShiftSpace
    case commandShiftD
    case controlOptionD
    case f13

    var id: String { rawValue }

    /// macOS virtual key code (`kVK_*`), which is layout-independent — the code
    /// for the physical D key is 2 whether the layout is Lithuanian or US.
    var keyCode: Int64 {
        switch self {
        case .optionSpace, .commandShiftSpace: return 49   // kVK_Space
        case .commandShiftD, .controlOptionD:  return 2    // kVK_ANSI_D
        case .f13:                             return 105  // kVK_F13
        }
    }

    /// Modifiers that must be held, matched **exactly**: ⌥Space must not fire
    /// when ⌘⌥Space is pressed, or the app would eat a shortcut it was never
    /// asked for.
    var modifiers: CGEventFlags {
        switch self {
        case .optionSpace:       return [.maskAlternate]
        case .commandShiftSpace: return [.maskCommand, .maskShift]
        case .commandShiftD:     return [.maskCommand, .maskShift]
        case .controlOptionD:    return [.maskControl, .maskAlternate]
        case .f13:               return []
        }
    }

    var displayName: String {
        switch self {
        case .optionSpace:       return "\u{2325}Space"
        case .commandShiftSpace: return "\u{2318}\u{21E7}Space"
        case .commandShiftD:     return "\u{2318}\u{21E7}D"
        case .controlOptionD:    return "\u{2303}\u{2325}D"
        case .f13:               return "F13"
        }
    }

    /// What this shortcut is known to clash with, shown beneath the picker.
    var conflictNote: String {
        switch self {
        case .optionSpace:
            return "Original default. Clashes if you use \u{2325}Space to switch input sources."
        case .commandShiftSpace:
            return "Usually free."
        case .commandShiftD:
            return "Claimed by some apps (Finder \u{201C}Go to Desktop\u{201D}, Safari bookmarks)."
        case .controlOptionD:
            return "Usually free."
        case .f13:
            return "Free, but missing from most laptop keyboards."
        }
    }

    /// Only these four are compared, so Caps Lock, fn and the numeric-pad flag
    /// can never prevent a match — `CGEventFlags` carries several bits that have
    /// nothing to do with the shortcut being pressed.
    static let relevantModifiers: CGEventFlags =
        [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        keyCode == self.keyCode
            && flags.intersection(Self.relevantModifiers) == modifiers
    }

    /// Unchanged from the hardcoded original, so an existing install behaves
    /// exactly as before until the user deliberately moves it.
    static let fallback: HotkeyCombo = .optionSpace
}
