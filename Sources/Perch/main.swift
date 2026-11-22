import AgentCore
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SessionStore()
    let actions = AppActions()
    let hooks = HookManager()
    let login = LoginItem()
    lazy var settings = SettingsWindowController(hooks: hooks, login: login)
    lazy var notch = NotchPanelController(store: store, actions: actions)

    func applicationDidFinishLaunching(_ notification: Notification) {
        hooks.refresh()
        actions.hooksInstalled = { [weak self] in self?.hooks.status == .installed }
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
        if ProcessInfo.processInfo.environment["PERCH_OPEN_SETTINGS"] == "1" { settings.show() }
    }

    /// Opening Perch.app again (Finder, Spotlight) shows Settings, since there is no Dock icon or menu.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
