import AgentCore
import AppKit
import ServiceManagement
import SwiftUI

/// Install state of the Claude Code hooks. Writes to `~/.claude/settings.json` only when the user clicks.
@MainActor
final class HookManager: ObservableObject {
    @Published private(set) var status: HookInstallStatus?
    @Published private(set) var problem: String?
    @Published private(set) var lastResult: String?

    let installer = ClaudeHookInstaller(
        settingsURL: PerchPaths.claudeSettings,
        hookCommand: PerchPaths.hookCommand(agent: "claude-code"))

    func refresh() {
        do {
            status = try installer.status()
            problem = nil
        } catch {
            status = nil
            problem = "\(error)"
        }
        // Keep the installed script current (it lives in Perch's own folder, not in ~/.claude).
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
            try? FileManager.default.removeItem(at: PerchPaths.hookScript)
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

    func set(_ on: Bool) {
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

struct SettingsView: View {
    @ObservedObject var hooks: HookManager
    @ObservedObject var login: LoginItem
    @State private var confirmInstall = false
    @State private var confirmUninstall = false

    var body: some View {
        Form {
            Section("Claude Code") {
                LabeledContent("Hooks") {
                    HStack(spacing: 6) {
                        Image(systemName: statusSymbol).foregroundStyle(statusColor)
                        Text(statusText)
                    }
                }
                Text("Perch adds one hook to \(ClaudeHookInstaller.events.count) events in ~/.claude/settings.json. Other tools' hooks stay as they are. A backup is saved next to the file before every change.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            Section("General") {
                Toggle("Open at login", isOn: Binding(get: { login.enabled }, set: { login.set($0) }))
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
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            hooks.refresh()
            login.refresh()
        }
        .alert("Install Claude Code hooks?", isPresented: $confirmInstall) {
            Button("Install") { hooks.install() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Perch will back up ~/.claude/settings.json, then add its hook to: \(ClaudeHookInstaller.events.joined(separator: ", ")). New Claude Code sessions pick it up; running ones may need a restart.")
        }
        .alert("Uninstall Claude Code hooks?", isPresented: $confirmUninstall) {
            Button("Uninstall", role: .destructive) { hooks.uninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Perch will back up ~/.claude/settings.json, then remove only its own hook entries.")
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

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let hooks: HookManager
    private let login: LoginItem

    init(hooks: HookManager, login: LoginItem) {
        self.hooks = hooks
        self.login = login
    }

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(hooks: hooks, login: login))
            let window = NSWindow(contentViewController: controller)
            window.title = "Perch Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        hooks.refresh()
        login.refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
