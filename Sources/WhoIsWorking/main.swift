import AgentCore
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SessionStore()
    let actions = AppActions()
    let installers = AgentInstallers()
    let login = LoginItem()
    lazy var settings = SettingsWindowController(installers: installers, login: login)
    lazy var setup = SetupModel(installers: installers, store: store)
    lazy var notch = NotchPanelController(store: store, setup: setup, actions: actions)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Refreshing also keeps the hook script current (UI-14); the OpenCode plugin is updated here only (OPC-09).
        installers.all.forEach { $0.refresh() }
        installers.openCode.updatePluginIfOutdated()
        actions.hooksInstalled = { [weak self] in
            self?.installers.all.contains { $0.status == .installed } ?? false
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
        // After the socket is up: a copy without it offers no setup (UI-16).
        setup.refresh()
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
