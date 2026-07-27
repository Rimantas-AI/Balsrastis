import AppKit
import SwiftUI

/// Owns the app's manually-managed windows: the Settings window and the floating
/// recording HUD. A menu-bar-only (`LSUIElement`) app has no automatic window
/// lifecycle, so both are created and shown here.
///
/// All methods are expected to be called on the main thread (menu actions and
/// the dictation coordinator already run there).
final class WindowManager {

    static let shared = WindowManager()
    private init() {}

    // MARK: – Settings

    private var settingsWindow: NSWindow?

    /// Opens (or re-focuses) the Settings window. Re-openable from the menu bar
    /// after the user closes it; never full screen, always closable.
    func showSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: controller)
            window.title = "OmniScribe Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            // Keep the instance alive after the user clicks the close button so it
            // can be re-shown; without this AppKit would deallocate it on close.
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        // A background app must activate itself for the settings window to focus.
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: – Recording HUD

    let hudState = RecordingHUDState()
    private var hudPanel: HUDPanel?
    private var errorDismissal: DispatchWorkItem?

    /// Shows the HUD without activating the app or taking focus.
    func showRecordingHUD(phase: HUDPhase = .listening) {
        errorDismissal?.cancel()
        hudState.phase = phase
        hudState.level = 0

        if hudPanel == nil {
            let hosting = NSHostingView(rootView: RecordingHUDView(state: hudState))
            hosting.frame = NSRect(x: 0, y: 0, width: phase.preferredWidth, height: 54)
            hudPanel = HUDPanel(contentView: hosting)
        }

        resizeHUD(for: phase)
        positionHUD()
        // orderFrontRegardless shows the panel without making the app active.
        hudPanel?.orderFrontRegardless()
    }

    /// Updates the HUD's visual phase (e.g. listening → transcribing) while visible.
    func updateHUD(phase: HUDPhase) {
        hudState.phase = phase
        resizeHUD(for: phase)
        positionHUD()
    }

    /// Feeds the live input-level meter.
    func updateLevel(_ level: Float) {
        hudState.level = level
    }

    /// Surfaces a failure to the user, then dismisses itself.
    ///
    /// Without this the pipeline's only failure channel was a console log, which
    /// is invisible in the way the app is normally launched.
    func showFailure(_ message: String, dismissAfter seconds: TimeInterval = 4) {
        showRecordingHUD(phase: .error(message))

        let work = DispatchWorkItem { [weak self] in self?.hideRecordingHUD() }
        errorDismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hideRecordingHUD() {
        errorDismissal?.cancel()
        hudPanel?.orderOut(nil)
    }

    // MARK: – Positioning

    /// Error text needs more room than "Listening…", so the panel follows the phase.
    private func resizeHUD(for phase: HUDPhase) {
        guard let panel = hudPanel else { return }
        let height: CGFloat = 54
        panel.setContentSize(NSSize(width: phase.preferredWidth, height: height))
        panel.contentView?.frame = NSRect(x: 0, y: 0, width: phase.preferredWidth, height: height)
    }

    /// Bottom-center of the active screen — visible but away from menu bar and
    /// most editing surfaces.
    private func positionHUD() {
        guard let panel = hudPanel, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.minY + 90
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
