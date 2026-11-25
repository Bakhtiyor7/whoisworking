import AgentCore
import AppKit
import ServiceManagement
import SwiftUI

/// What Settings needs from an installer: hook entries in an agent's file, or the OpenCode plugin file.
protocol AgentInstalling: Sendable {
    func status() throws -> HookInstallStatus
    func install() throws -> HookInstaller.Result
    func uninstall() throws -> HookInstaller.Result
}

extension HookInstaller: AgentInstalling {}
extension PluginInstaller: AgentInstalling {}

/// Install state of one agent's hooks (or plugin). Writes to the agent's files only when the user clicks,
/// except that launch keeps WhoIsWorking's own hook script and plugin file current (UI-14, OPC-09).
@MainActor
final class HookManager: ObservableObject {
    @Published private(set) var status: HookInstallStatus?
    @Published private(set) var problem: InstallerProblem?
    @Published private(set) var lastResult: String?

    let installer: any AgentInstalling
    let agent: AgentKind
    /// The agent's hook file, or the plugin file.
    let fileURL: URL
    /// `~/…` path shown in Settings.
    let displayPath: String
    /// Event names; empty for the plugin file.
    let events: [String]
    /// Hook entries call the shared hook script; the OpenCode plugin talks to the socket itself.
    let usesHookScript: Bool

    init(target: HookTarget) {
        installer = HookInstaller(
            target: target, settingsURL: target.defaultSettingsURL,
            hookCommand: AppPaths.hookCommand(agent: target.id))
        agent = target.agent
        fileURL = target.defaultSettingsURL
        displayPath = "~/" + target.defaultSettingsPath
        events = target.events
        usesHookScript = true
    }

    /// The OpenCode plugin file (OPC-01).
    init(plugin: PluginInstaller) {
        installer = plugin
        agent = .openCode
        fileURL = plugin.fileURL
        displayPath = plugin.fileURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        events = []
        usesHookScript = false
    }

    var isPlugin: Bool { !usesHookScript }

    /// True while `problem` holds a failed status read, not a message from an install or a plugin update.
    private var problemIsFromRead = false

    /// Reads the status again and writes nothing (the setup card does this, UI-17). It leaves a
    /// message from a failed install or plugin update in place; only a new look in Settings clears that.
    func reloadStatus() {
        do {
            let read = try installer.status()
            if read != status { status = read }
            if problemIsFromRead {
                problem = nil
                problemIsFromRead = false
            }
        } catch {
            if status != nil { status = nil }
            problem = InstallerProblem(error, action: .read, agent: agent)
            problemIsFromRead = true
        }
    }

    func refresh() {
        reloadStatus()
        if !problemIsFromRead { problem = nil }
        // Keep the installed script current (it lives in the app's own folder, not in the agent's).
        if usesHookScript, status == .installed || status == .partial, !HookScript.isCurrent(at: AppPaths.hookScript) {
            try? HookScript.write(to: AppPaths.hookScript)
        }
    }

    /// At launch only: replaces an outdated copy of WhoIsWorking's own plugin, with a backup (OPC-09).
    func updatePluginIfOutdated() {
        guard let plugin = installer as? PluginInstaller else { return }
        var failure: InstallerProblem?
        do {
            if try plugin.updateIfOutdated() { lastResult = "Updated the plugin to this version." }
        } catch {
            failure = InstallerProblem(error, action: .update, agent: agent)
        }
        refresh()
        if let failure {  // shown in Settings, after refresh cleared the old one
            problem = failure
            problemIsFromRead = false
        }
    }

    /// Returns what the installer did, or nil when it refused or failed (`problem` then says why).
    @discardableResult
    func install() -> HookInstaller.Result? {
        let result: HookInstaller.Result
        do {
            if usesHookScript { try HookScript.write(to: AppPaths.hookScript) }
            result = try installer.install()
            lastResult = result.backupURL.map { "Installed. Backup: \($0.lastPathComponent)" }
                ?? (result.changed ? "Installed." : "Already installed; nothing changed.")
        } catch {
            lastResult = nil
            problem = InstallerProblem(error, action: .add, agent: agent)
            problemIsFromRead = false
            return nil
        }
        refresh()
        return result
    }

    func uninstall() {
        do {
            let result = try installer.uninstall()
            // The script is shared by all agents; it goes only when no agent's hooks still use it.
            if usesHookScript { HookScript.removeIfUnused(at: AppPaths.hookScript) }
            lastResult = result.backupURL.map { "Removed. Backup: \($0.lastPathComponent)" }
                ?? (result.changed ? "Removed." : "Not installed; nothing changed.")
        } catch {
            lastResult = nil
            problem = InstallerProblem(error, action: .remove, agent: agent)
            problemIsFromRead = false
            return
        }
        refresh()
    }
}

@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var note: String?

    /// SMAppService needs a real app bundle that stays where it is (DST-10).
    private let location = RunLocation.classify(bundlePath: Bundle.main.bundlePath)
    var available: Bool { location == .installed }

    func refresh() {
        guard available else {
            enabled = false
            switch location {
            case .diskImage, .translocated:
                note = "Move Who's Working to the Applications folder and open it from there to use this."
            case .notBundle, .installed:
                note = "Available when Who's Working runs as WhoIsWorking.app (scripts/bundle.sh)."
            }
            return
        }
        let status = SMAppService.mainApp.status
        enabled = status == .enabled
        note = status == .requiresApproval ? "Allow Who's Working in System Settings › General › Login Items." : nil
    }

    func update(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            note = error.localizedDescription
        }
        let message = note
        refresh()
        if note == nil { note = message }
    }
}

struct HooksSection: View {
    let title: String
    let note: String?
    @ObservedObject var hooks: HookManager
    @State private var confirmInstall = false
    @State private var confirmUninstall = false

    /// "hooks" or "plugin".
    private var noun: String { hooks.isPlugin ? "plugin" : "hooks" }

    private var explanation: String { SetupPrompt.settingsExplanation(for: hooks.agent) }

    var body: some View {
        Section(title) {
            LabeledContent(hooks.isPlugin ? "Plugin" : "Hooks") {
                HStack(spacing: 6) {
                    Image(systemName: statusSymbol).foregroundStyle(statusColor)
                    Text(statusText)
                }
            }
            Text(explanation)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(hooks.status == .installed ? "Reinstall \(noun)" : "Install \(noun)…") { confirmInstall = true }
                Button("Uninstall \(noun)…") { confirmUninstall = true }
                    .disabled(hooks.status == .notInstalled || hooks.status == nil)
            }
            if let problem = hooks.problem {
                // ONB-06: the cause and the fix, then the raw detail on a dimmer line.
                VStack(alignment: .leading, spacing: 2) {
                    Text(problem.text).font(.callout).foregroundStyle(.red)
                    if let detail = problem.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            }
            if let last = hooks.lastResult {
                Text(last).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .alert("Install \(title) \(noun)?", isPresented: $confirmInstall) {
            Button("Install") { hooks.install() }
            Button("Cancel", role: .cancel) {}
        } message: {
            // The same consent text as the card (ONB-01), plus the event names, which the card leaves out.
            let consent = SetupPrompt.confirmation(
                for: hooks.agent, fileExists: FileManager.default.fileExists(atPath: hooks.fileURL.path), place: "in the notch")
            Text(hooks.isPlugin
                ? "\(consent) OpenCode loads the plugin the next time it starts."
                : "\(consent) Events: \(hooks.events.joined(separator: ", ")).")
        }
        .alert("Uninstall \(title) \(noun)?", isPresented: $confirmUninstall) {
            Button("Uninstall", role: .destructive) { hooks.uninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(hooks.isPlugin
                ? "Who's Working will delete \(hooks.displayPath) and nothing else."
                : "Who's Working backs up \(hooks.displayPath), then removes only its own hook entries. Your other hooks stay as they are.")
        }
    }

    private var statusText: String {
        switch hooks.status {
        case .installed: "Installed"
        case .partial: "Partly installed. Reinstall to fix it."
        case .notInstalled: "Not installed"
        case nil: "Unknown"
        }
    }

    private var statusSymbol: String {
        switch hooks.status {
        case .installed: "checkmark.circle.fill"
        case .partial: "exclamationmark.circle.fill"
        default: "circle"
        }
    }

    private var statusColor: Color {
        switch hooks.status {
        case .installed: .green
        case .partial: .orange
        default: .secondary
        }
    }
}

/// The installers Settings shows, one per agent, in a fixed order.
@MainActor
struct AgentInstallers {
    let claude = HookManager(target: .claudeCode)
    let codex = HookManager(target: .codex)
    let cursor = HookManager(target: .cursor)
    let openCode = HookManager(plugin: PluginInstaller())
    let antigravity = HookManager(target: .antigravity)

    var all: [HookManager] { [claude, codex, cursor, openCode, antigravity] }

    func manager(for agent: AgentKind) -> HookManager {
        switch agent {
        case .claudeCode: claude
        case .codex: codex
        case .cursor: cursor
        case .openCode: openCode
        case .antigravity: antigravity
        }
    }
}

struct SettingsView: View {
    let installers: AgentInstallers
    @ObservedObject var login: LoginItem
    @StateObject private var updates = UpdateChecker()

    var body: some View {
        ScrollViewReader { proxy in
        Form {
            HooksSection(
                title: "Claude Code",
                note: "New sessions pick up the hook. Restart sessions that were already running.",
                hooks: installers.claude)
            HooksSection(
                title: "Codex",
                note: "Codex needs one more step: it runs a new hook only after you trust it. In the Codex CLI, type /hooks and trust the Who's Working entries. In the Codex app, use Review hooks (or Settings › Hooks). Until you trust them, Codex skips the hooks.",
                hooks: installers.codex)
            HooksSection(
                title: "Cursor (experimental)",
                note: "Covers the Cursor app and cursor-agent: working, done and errors. Cursor's hooks cannot report a waiting approval. Not yet checked against a live Cursor session.",
                hooks: installers.cursor)
            HooksSection(
                title: "OpenCode",
                note: "For OpenCode 2. Restart running OpenCode sessions to load the plugin.",
                hooks: installers.openCode)
            HooksSection(
                title: "Antigravity (experimental)",
                note: "Not yet checked against a live Antigravity session. If your hooks.json has comments, Who's Working leaves it alone. If you turned the Who's Working hooks off in Antigravity, they stay off and show as partly installed.",
                hooks: installers.antigravity)
            Section("General") {
                Toggle("Open at login", isOn: Binding(get: { login.enabled }, set: { login.update($0) }))
                    .disabled(!login.available)
                if let note = login.note {
                    Text(note).font(.callout).foregroundStyle(.secondary)
                }
                UpdateRows(updates: updates)
            }
            Section {
                HStack {
                    Text("Who's Working \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit Who's Working") { NSApp.terminate(nil) }
                }
            }
            .id("bottom")
        }
        .formStyle(.grouped)
        // Five agents no longer fit a short screen, so the form scrolls.
        .frame(width: 480, height: 640)
        .onAppear {
            installers.all.forEach { $0.refresh() }
            login.refresh()
            // Debug snapshots only (WHOISWORKING_FAKE_LATEST): answer from the file, no network, and
            // scroll to the General section so the snapshot shows the result.
            if updates.isFaked {
                updates.check()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        }
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let installers: AgentInstallers
    private let login: LoginItem

    init(installers: AgentInstallers, login: LoginItem) {
        self.installers = installers
        self.login = login
    }

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(installers: installers, login: login))
            let window = NSWindow(contentViewController: controller)
            window.title = "Who's Working Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        installers.all.forEach { $0.refresh() }
        login.refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
