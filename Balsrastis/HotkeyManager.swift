import AppKit
import ApplicationServices

/// Installs a global `CGEventTap` that intercepts the user's chosen shortcut
/// (`AppPreferences.hotkey`, see `HotkeyCombo`) system-wide.
///
/// Design decisions:
/// - Uses `CGEventTap` (not `NSEvent.addGlobalMonitorForEvents`) so the event
///   can be *consumed* (return `nil`) and never reaches the focused application.
/// - The tap callback is a bare C function pointer; `self` is threaded through
///   via `userInfo` using `Unmanaged` to avoid a retain cycle.
/// - Weak references to `MenuBarManager` prevent a retain cycle if the manager
///   is ever deallocated.
/// - If the system disables the tap after a timeout, it is automatically re-enabled.
final class HotkeyManager {

    /// Invoked on the main queue every time the chosen shortcut is pressed. The
    /// coordinator decides what to do (start vs. stop dictation) so this class
    /// stays a pure input source with no knowledge of the audio pipeline.
    private let onTrigger: () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Whether the event tap is actually running.
    ///
    /// `false` means the shortcut is dead — Accessibility was not granted when
    /// the app launched, and `install()` returned without creating the tap. It
    /// is not retried, so the app must be relaunched after granting. This used
    /// to be reported only by a `print`, which meant the shortcut silently did
    /// nothing and the menu button was the only way in.
    private(set) static var isInstalled = false

    /// Set while Settings is capturing a new shortcut.
    ///
    /// The tap is session-wide, so it sees the keys being recorded too — without
    /// this, pressing the *current* shortcut in order to replace it would start a
    /// dictation instead. Only ever touched from the main thread: the recorder
    /// runs in the Settings UI and the tap callback is delivered on the main run
    /// loop it was installed on.
    static var isRecording = false

    // MARK: – Init / Deinit

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        install()
    }

    deinit {
        uninstall()
    }

    // MARK: – Install

    private func install() {
        guard AXIsProcessTrusted() else {
            Self.isInstalled = false
            print("[HotkeyManager] ⚠️  Accessibility not granted – event tap NOT installed. " +
                  "Grant access in System Settings and relaunch.")
            return
        }

        // Listen only to keyDown events to keep the tap as lightweight as possible.
        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue

        // The callback must be a C-compatible function pointer (no Swift captures).
        // We pass `self` via `userInfo` instead.
        let callback: CGEventTapCallBack = { _, type, event, userInfo -> Unmanaged<CGEvent>? in
            guard let userInfo else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            return manager.handle(type: type, event: event)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,        // Session-level: fires for every app.
            place: .headInsertEventTap,     // First to see the event.
            options: .defaultTap,           // Can modify/consume events.
            eventsOfInterest: mask,
            callback: callback,
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            print("[HotkeyManager] ❌ CGEvent tap creation failed. " +
                  "Accessibility permission is required.")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        Self.isInstalled = true
        print("[HotkeyManager] ✅ Global hotkey \(AppPreferences.shared.hotkey.displayName) registered.")
    }

    // MARK: – Uninstall

    private func uninstall() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        print("[HotkeyManager] Global hotkey unregistered.")
    }

    // MARK: – Event Handling

    /// Decides whether to consume or pass through each keyboard event.
    /// Returns `nil` to consume (swallow) the event, or the original event to let it through.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables taps that take too long. Re-enable and bail.
        if type == .tapDisabledByTimeout {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil
        }

        // Let every key through untouched while Settings is recording a new
        // shortcut, so the recorder sees the real keypress and no dictation
        // starts behind the Settings window.
        guard !Self.isRecording else { return Unmanaged.passRetained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Read live rather than caching at install time, so changing the
        // shortcut in Settings takes effect on the next keypress without
        // tearing down and reinstalling the tap (which would re-prompt nothing
        // but is one more thing to get wrong). This callback runs on the main
        // run loop the tap was added to, so reading shared state is safe here.
        let combo = AppPreferences.shared.hotkey

        guard combo.matches(keyCode: keyCode, flags: event.flags) else {
            return Unmanaged.passRetained(event)  // Not our shortcut – pass through.
        }

        // Dispatch UI work to main. The callback may arrive on a background thread.
        DispatchQueue.main.async { [weak self] in
            self?.didTriggerHotkey()
        }

        return nil  // Consume the event so the focused app never sees it.
    }

    // MARK: – Hotkey Action

    private func didTriggerHotkey() {
        print("[HotkeyManager] 🎤 \(AppPreferences.shared.hotkey.displayName) triggered")
        onTrigger()
    }
}
