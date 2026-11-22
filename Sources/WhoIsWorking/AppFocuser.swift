import AgentCore
import AppKit

/// Brings the app that owns a session to the front (best effort).
///
/// Walks up the session process's parent chain to the first regular app: Terminal, iTerm2,
/// VS Code, Cursor or Claude.app. It cannot pick a specific terminal tab or a specific
/// conversation inside Claude.app; it only brings that app forward.
@MainActor
enum AppFocuser {
    static let claudeDesktopBundleID = "com.anthropic.claudefordesktop"

    @discardableResult
    static func focus(_ session: Session, probe: ProcessProbe = .system) -> Bool {
        if let pid = session.pid, let app = owningApp(of: pid, probe: probe) {
            activate(app)
            return true
        }
        if session.entrypoint == "claude-desktop",
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: claudeDesktopBundleID).first
        {
            activate(app)
            return true
        }
        return false
    }

    static func owningApp(of pid: Int32, probe: ProcessProbe) -> NSRunningApplication? {
        var current: Int32? = pid
        var steps = 0
        while let p = current, p > 1, steps < 32 {
            if let app = NSRunningApplication(processIdentifier: p), app.activationPolicy == .regular {
                return app
            }
            current = probe.parent(of: p)
            steps += 1
        }
        return nil
    }

    private static func activate(_ app: NSRunningApplication) {
        app.unhide()
        if let url = app.bundleURL {
            // Opening the running app is the most reliable way for a background app to hand over focus.
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        } else {
            app.activate()
        }
    }
}
