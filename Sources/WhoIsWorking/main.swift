import AgentCore
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SessionStore()
    let actions = AppActions()
    let claudeHooks = HookManager(target: .claudeCode)
    let codexHooks = HookManager(target: .codex)
    let login = LoginItem()
    lazy var settings = SettingsWindowController(claude: claudeHooks, codex: codexHooks, login: login)
    lazy var notch = NotchPanelController(store: store, actions: actions)

    func applicationDidFinishLaunching(_ notification: Notification) {
        claudeHooks.refresh()
        codexHooks.refresh()
        actions.hooksInstalled = { [weak self] in
            self?.claudeHooks.status == .installed || self?.codexHooks.status == .installed
        }
        actions.openSettings = { [weak self] in
            self?.notch.collapse()
            self?.settings.show()
        }
        actions.openSession = { [weak self] session in
            self?.store.markViewed([session.id])
            self?.notch.collapse()
            if !AppFocuser.focus(session) { NSSound.beep() }
        }
        store.start()
        notch.show()
        if ProcessInfo.processInfo.environment["WHOISWORKING_OPEN_SETTINGS"] == "1" { settings.show() }
    }

    /// Opening WhoIsWorking.app again (Finder, Spotlight) shows Settings, since there is no Dock icon or menu.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }
}

if CommandLine.arguments.count > 1, CommandLine.arguments[1] == "hooks" {
    exit(HooksCommand.run(Array(CommandLine.arguments.dropFirst(2))))
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
