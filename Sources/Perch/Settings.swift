import AgentCore
import AppKit
import ServiceManagement
import SwiftUI

/// Install state of one agent's hooks. Writes to the agent's hook file only when the user clicks.
@MainActor
final class HookManager: ObservableObject {
    @Published private(set) var status: HookInstallStatus?
    @Published private(set) var problem: String?
    @Published private(set) var lastResult: String?

    let target: HookTarget
    let installer: HookInstaller

    init(target: HookTarget) {
        self.target = target
        installer = HookInstaller(
            target: target, settingsURL: target.defaultSettingsURL,
            hookCommand: PerchPaths.hookCommand(agent: target.id))
    }

    var displayPath: String { "~/" + target.defaultSettingsPath }

    func refresh() {
        do {
            status = try installer.status()
            problem = nil
        } catch {
            status = nil
            problem = "\(error)"
        }
        // Keep the installed script current (it lives in Perch's own folder, not in the agent's).
        if status == .installed || status == .partial, !HookScript.isCurrent(at: PerchPaths.hookScript) {
            try? HookScript.write(to: PerchPaths.hookScript)
        }
    }

    func install() {
        do {
            try HookScript.write(to: PerchPaths.hookScript)
            let result = try installer.install()
            lastResult = result.backupURL.map { "Installed. Backup: \($0.lastPathComponent)" }
                ?? (result.changed ? "Installed." : "Already installed; nothing changed.")
        } catch {
            lastResult = nil
            problem = "\(error)"
            return
        }
        refresh()
    }

    func uninstall() {
        do {
            let result = try installer.uninstall()
            // The script is shared by all agents; it goes only when no agent's hooks still use it.
            HookScript.removeIfUnused(at: PerchPaths.hookScript)
            lastResult = result.backupURL.map { "Removed. Backup: \($0.lastPathComponent)" }
                ?? (result.changed ? "Removed." : "Not installed; nothing changed.")
        } catch {
            lastResult = nil
            problem = "\(error)"
            return
        }
        refresh()
    }
}

@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var note: String?

    /// SMAppService needs a real app bundle; `swift run` builds are not one.
    var available: Bool { Bundle.main.bundlePath.hasSuffix(".app") }

    func refresh() {
        guard available else {
            enabled = false
            note = "Available when Perch runs as Perch.app (scripts/bundle.sh)."
            return
        }
        let status = SMAppService.mainApp.status
        enabled = status == .enabled
        note = status == .requiresApproval ? "Allow Perch in System Settings › General › Login Items." : nil
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

    var body: some View {
        Section(title) {
            LabeledContent("Hooks") {
                HStack(spacing: 6) {
                    Image(systemName: statusSymbol).foregroundStyle(statusColor)
                    Text(statusText)
                }
            }
            Text("Perch adds one hook to \(hooks.target.events.count) events in \(hooks.displayPath). Other tools' hooks stay as they are. A backup is saved next to the file before every change.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(hooks.status == .installed ? "Reinstall hooks" : "Install hooks…") { confirmInstall = true }
                Button("Uninstall hooks…") { confirmUninstall = true }
                    .disabled(hooks.status == .notInstalled || hooks.status == nil)
            }
            if let problem = hooks.problem {
                Text(problem).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            if let last = hooks.lastResult {
                Text(last).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .alert("Install \(title) hooks?", isPresented: $confirmInstall) {
            Button("Install") { hooks.install() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Perch will back up \(hooks.displayPath), then add its hook to: \(hooks.target.events.joined(separator: ", ")).")
        }
        .alert("Uninstall \(title) hooks?", isPresented: $confirmUninstall) {
            Button("Uninstall", role: .destructive) { hooks.uninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Perch will back up \(hooks.displayPath), then remove only its own hook entries.")
        }
    }

    private var statusText: String {
        switch hooks.status {
        case .installed: "Installed"
        case .partial: "Partly installed — reinstall to fix"
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

struct SettingsView: View {
    @ObservedObject var claude: HookManager
    @ObservedObject var codex: HookManager
    @ObservedObject var login: LoginItem

    var body: some View {
        Form {
            HooksSection(
                title: "Claude Code",
                note: "New sessions pick the hooks up; running ones may need a restart.",
                hooks: claude)
            HooksSection(
                title: "Codex",
                note: "Codex runs new hooks only after you trust them. In the Codex CLI type /hooks and trust the Perch entries; in the Codex app use Review hooks (or Settings › Hooks). Until then Codex skips them.",
                hooks: codex)
            Section("General") {
                Toggle("Open at login", isOn: Binding(get: { login.enabled }, set: { login.update($0) }))
                    .disabled(!login.available)
                if let note = login.note {
                    Text(note).font(.callout).foregroundStyle(.secondary)
                }
            }
            Section {
                HStack {
                    Text("Perch \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit Perch") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            claude.refresh()
            codex.refresh()
            login.refresh()
        }
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let claude: HookManager
    private let codex: HookManager
    private let login: LoginItem

    init(claude: HookManager, codex: HookManager, login: LoginItem) {
        self.claude = claude
        self.codex = codex
        self.login = login
    }

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(claude: claude, codex: codex, login: login))
            let window = NSWindow(contentViewController: controller)
            window.title = "Perch Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        claude.refresh()
        codex.refresh()
        login.refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
