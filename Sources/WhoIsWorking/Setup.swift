import AgentCore
import AppKit
import Combine
import SwiftUI

/// Feeds the setup hint and the setup card (UI-16, UI-17): reads the installers and the
/// "Later" and "Skip" preferences, and lets `SetupPrompt` in AgentCore decide what is shown.
@MainActor
final class SetupModel: ObservableObject {
    @Published private(set) var prompt = SetupPrompt(
        ownsSocket: false, dismissal: SetupDismissal(), now: Date(), found: [], statuses: [:])
    /// The row whose confirmation is open; nothing is written until its Install is clicked.
    @Published private(set) var confirming: AgentKind?
    /// What the last install from the card left to say about an agent: a refusal, or a repair that is still partial.
    @Published private(set) var messages: [AgentKind: Message] = [:]

    struct Message: Equatable {
        var text: String
        var isError: Bool
    }

    private let installers: AgentInstallers
    private let store: SessionStore
    private var installedNow = Set<AgentKind>()
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    /// A snapshot preview shows card states; its buttons write nothing.
    private let isPreview: Bool
    private static let dismissedAtKey = "setupDismissedAt"
    private static let skippedKey = "setupSkippedAgents"
    /// Skips shown by a snapshot preview; a preview never reads or writes the saved ones.
    private var previewSkipped = Set<AgentKind>()

    /// Agents the user said never to offer, from the preferences.
    private var skippedAgents: Set<AgentKind> {
        if isPreview { return previewSkipped }
        let saved = UserDefaults.standard.stringArray(forKey: Self.skippedKey) ?? []
        return Set(saved.compactMap(AgentKind.init(rawValue:)))
    }

    /// How often and when the user closed setup, from the preferences.
    private var dismissal: SetupDismissal {
        let defaults = UserDefaults.standard
        return SetupDismissal(lastAt: defaults.object(forKey: Self.dismissedAtKey) as? Date)
    }
    /// How often the statuses are read again while the app runs, so hooks removed elsewhere bring the hint back.
    static let rereadInterval: TimeInterval = 15

    init(installers: AgentInstallers, store: SessionStore) {
        self.installers = installers
        self.store = store
        // `WHOISWORKING_SETUP_PREVIEW=confirm:codex` or `installed:codex`: card states for snapshots.
        let preview = ProcessInfo.processInfo.environment["WHOISWORKING_SETUP_PREVIEW"]
        isPreview = preview != nil
        if let preview {
            let parts = preview.split(separator: ":").map(String.init)
            if parts.count == 2, let agent = AgentKind(rawValue: parts[1]) {
                if parts[0] == "confirm" { confirming = agent }
                if parts[0] == "installed" { installedNow.insert(agent) }
                if parts[0] == "skipped" { previewSkipped.insert(agent) }
            }
        }
        // Installs and uninstalls made in Settings change the hint too.
        for manager in installers.all {
            manager.$status.dropFirst().sink { [weak self] _ in
                DispatchQueue.main.async { self?.recompute() }
            }.store(in: &cancellables)
        }
        // The socket can be won later (after wake), and only a copy that owns it offers setup.
        store.$socketError.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.recompute() }
        }.store(in: &cancellables)
        timer = Timer.scheduledTimer(withTimeInterval: Self.rereadInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Reads every agent's status again, without writing anything, and rebuilds the prompt.
    func refresh() {
        installers.all.forEach { $0.reloadStatus() }
        recompute()
    }

    private func recompute() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var statuses: [AgentKind: HookInstallStatus] = [:]
        for manager in installers.all { statuses[manager.agent] = manager.status }
        let next = SetupPrompt(
            ownsSocket: store.ownsSocket,
            dismissal: dismissal,
            now: Date(),
            found: SetupPrompt.agentsFound(home: home),
            statuses: statuses,
            installedNow: installedNow,
            skipped: skippedAgents)
        if next != prompt { prompt = next }
        if let open = confirming, !next.rows.contains(where: { $0.agent == open && $0.action != nil }) { confirming = nil }
    }

    func confirmation(for agent: AgentKind) -> String {
        let exists = FileManager.default.fileExists(atPath: installers.manager(for: agent).fileURL.path)
        return SetupPrompt.confirmation(for: agent, fileExists: exists)
    }

    /// What to show under a row: the result of an install from the card, or why its file cannot be read.
    func message(for agent: AgentKind) -> Message? {
        if let message = messages[agent] { return message }
        let manager = installers.manager(for: agent)
        if manager.status == nil, let problem = manager.problem { return Message(text: problem, isError: true) }
        return nil
    }

    /// "Connect" or "Repair": opens the confirmation in that row. Writes nothing.
    func askToInstall(_ agent: AgentKind) {
        guard prompt.rows.contains(where: { $0.agent == agent && $0.action != nil }) else { return }
        messages[agent] = nil
        confirming = agent
    }

    func cancelConfirmation() {
        if confirming != nil { confirming = nil }
    }

    /// "Install" in the confirmation: the same call Settings makes after its alert. It only acts for
    /// the row whose confirmation is open, so no other click can write.
    func install(_ agent: AgentKind) {
        guard !isPreview, confirming == agent,
              prompt.rows.contains(where: { $0.agent == agent && $0.action != nil })
        else { return }
        confirming = nil
        let manager = installers.manager(for: agent)
        if let result = manager.install() {
            if SetupPrompt.countsAsInstalledNow(changed: result.changed, status: manager.status) {
                installedNow.insert(agent)
            } else if manager.status != .installed {
                messages[agent] = Message(text: SetupPrompt.stillPartialNote(for: agent), isError: false)
            }
        } else {
            messages[agent] = Message(text: manager.problem ?? "The install failed.", isError: true)
            // The file may have changed since the confirmation opened: show what is there now.
            manager.reloadStatus()
        }
        recompute()
    }

    /// "Later" or "Done": the hint and the card are off for a week, every time.
    func dismiss() {
        guard !isPreview, prompt.showsCard else { return }
        UserDefaults.standard.set(dismissal.closed(at: Date()).lastAt, forKey: Self.dismissedAtKey)
        confirming = nil
        recompute()
    }

    /// "Skip" on a row: that agent is not offered again. Writes a preference and nothing else.
    func skip(_ agent: AgentKind) {
        guard !isPreview, prompt.rows.contains(where: { $0.agent == agent && $0.canSkip }) else { return }
        saveSkipped(skippedAgents.union([agent]))
        if confirming == agent { confirming = nil }
        messages[agent] = nil
        recompute()
    }

    /// "Undo" beside a skipped agent: it is offered again.
    func undoSkip(_ agent: AgentKind) {
        guard !isPreview, prompt.skipped.contains(agent) else { return }
        saveSkipped(skippedAgents.subtracting([agent]))
        recompute()
    }

    private func saveSkipped(_ agents: Set<AgentKind>) {
        // Stored in the fixed agent order, so the saved value does not depend on the order of the clicks.
        let ordered = AgentKind.allCases.filter(agents.contains).map(\.rawValue)
        UserDefaults.standard.set(ordered, forKey: Self.skippedKey)
    }
}

/// The setup hint in the wings: a plug and "Set up", white so that amber keeps meaning a session waits.
struct SetupWings: View {
    var body: some View {
        HStack {
            Image(systemName: "powerplug.fill").font(.system(size: 12, weight: .semibold))
            Spacer()
            Text("Set up").font(.system(size: 13, weight: .semibold))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Who's Working needs setup")
        .accessibilityHint("Move the pointer here to connect your agents")
    }
}

/// "Finish setup": the agents found on this Mac, each with a button that installs its hooks after
/// a confirmation inside the row.
struct SetupCard: View {
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(spacing: 6) {
            SectionLabel(text: "FINISH SETUP", color: .white)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Connect your agents").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button(setup.prompt.closeTitle) { setup.dismiss() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.dim)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                        .accessibilityHint(setup.prompt.closeHint)
                }
                Text("Who's Working learns about a session from its agent's hooks.")
                    .font(.system(size: 12)).foregroundStyle(Palette.dim)
                VStack(spacing: 2) {
                    ForEach(setup.prompt.rows) { row in SetupRow(row: row, setup: setup) }
                }
                if !setup.prompt.skipped.isEmpty {
                    SkippedLine(agents: setup.prompt.skipped, undo: setup.undoSkip)
                }
                Text("All agents, and uninstall, are in Settings.")
                    .font(.system(size: 11)).foregroundStyle(Palette.dim)
            }
            .padding(14)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .accessibilityElement(children: .contain)
    }
}

/// "Skipped: Cursor Undo · Antigravity Undo": the agents the user said never to offer, each with a way back.
struct SkippedLine: View {
    let agents: [AgentKind]
    let undo: (AgentKind) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("Skipped:").foregroundStyle(Palette.dim)
            ForEach(Array(agents.enumerated()), id: \.element) { index, agent in
                if index > 0 { Text("·").foregroundStyle(Palette.dim) }
                Text(agent.displayName).foregroundStyle(Palette.dim)
                Button("Undo") { undo(agent) }
                    .buttonStyle(.plain)
                    .underline()
                    .frame(height: 24)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Undo skipping \(agent.displayName)")
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
    }
}

struct SetupRow: View {
    let row: SetupPrompt.Row
    @ObservedObject var setup: SetupModel

    private var confirming: Bool { setup.confirming == row.agent }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                AgentMark(agent: row.agent)
                Text(row.agent.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .frame(width: 104, alignment: .leading)
                statusIcon
                Text(row.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.dim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if row.canSkip, !confirming {
                    Button("Skip") { setup.skip(row.agent) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.dim)
                        .padding(.horizontal, 6)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Skip \(row.agent.displayName)")
                        .accessibilityHint("Stops offering this agent. You can undo it below, or install it in Settings.")
                }
                if let action = row.action, !confirming {
                    let title = action == .connect ? "Connect" : "Repair"
                    Button(title) { setup.askToInstall(row.agent) }
                        .buttonStyle(SetupButtonStyle(prominent: true))
                        .accessibilityLabel("\(title) \(row.agent.displayName)")
                        .accessibilityHint("Shows what will change before anything is written")
                }
            }
            .frame(height: 44)
            if confirming {
                VStack(alignment: .leading, spacing: 8) {
                    Text(setup.confirmation(for: row.agent))
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Spacer()
                        Button("Cancel") { setup.cancelConfirmation() }
                            .buttonStyle(SetupButtonStyle(prominent: false))
                        Button("Install") { setup.install(row.agent) }
                            .buttonStyle(SetupButtonStyle(prominent: true))
                            .accessibilityLabel("Install for \(row.agent.displayName)")
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if let next = row.nextStep {
                Label(next, systemImage: "arrow.turn.down.right")
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 34).padding(.bottom, 4)
            }
            if let message = setup.message(for: row.agent) {
                Text(message.text)
                    .font(.system(size: 12)).foregroundStyle(message.isError ? Palette.red : Palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.leading, 34).padding(.bottom, 4)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(row.agent.displayName), \(row.detail)")
    }

    /// Every state has a shape of its own, so it reads without colour (UI-05).
    @ViewBuilder private var statusIcon: some View {
        switch row.status {
        case .installed:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(Palette.green)
        case .partial:
            Image(systemName: "exclamationmark.circle").font(.system(size: 13)).foregroundStyle(.white)
        case .notInstalled:
            Image(systemName: "circle.dashed").font(.system(size: 13)).foregroundStyle(Palette.dim)
        case nil:
            Image(systemName: "questionmark.circle").font(.system(size: 13)).foregroundStyle(Palette.dim)
        }
    }
}

/// A capsule button for the black panel: white for the action, grey for Cancel.
struct SetupButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(prominent ? .black : .white)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(prominent ? Color.white : Color(white: 0.2), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}
