import Foundation
import Testing
@testable import AgentCore

/// UI-16 and UI-17: the setup hint in the notch and the setup card in the panel.
@Suite("Setup prompt")
struct SetupPromptTests {
    private let nothing: [AgentKind: HookInstallStatus] = Dictionary(
        uniqueKeysWithValues: AgentKind.allCases.map { ($0, .notInstalled) })

    private func prompt(
        ownsSocket: Bool = true, dismissed: Bool = false, found: Set<AgentKind> = [.claudeCode, .codex],
        _ statuses: [AgentKind: HookInstallStatus], installedNow: Set<AgentKind> = [], skipped: Set<AgentKind> = []
    ) -> SetupPrompt {
        // "Dismissed" here means put off with Later a moment ago.
        let dismissal = dismissed ? SetupDismissal(lastAt: start) : SetupDismissal()
        return SetupPrompt(
            ownsSocket: ownsSocket, dismissal: dismissal, now: start, found: found, statuses: statuses,
            installedNow: installedNow, skipped: skipped)
    }

    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 3600

    private func with(_ changes: [AgentKind: HookInstallStatus]) -> [AgentKind: HookInstallStatus] {
        nothing.merging(changes) { _, new in new }
    }

    private func waiting(_ id: String) -> Session {
        Session(id: id, state: .needsApproval, stateSince: Date(timeIntervalSince1970: 1_000), lastEventAt: Date(timeIntervalSince1970: 1_000))
    }

    // MARK: The hint (UI-16)

    @Test func noConnectedAgentShowsTheSetupWings() {
        let p = prompt(nothing)
        #expect(p.showsWings)
        #expect(p.showsCard)
        let quiet = NotchSummary(sessions: [Session](), now: Date(timeIntervalSince1970: 1_060))
        #expect(CollapsedNotch(summary: quiet, setup: p) == .setup)
        // With setup done or dismissed, nothing is drawn while nothing needs the user (UI-01).
        #expect(CollapsedNotch(summary: quiet, setup: prompt(dismissed: true, nothing)) == .hidden)
    }

    @Test func aSessionThatNeedsYouTakesTheWingsFromSetup() {
        let summary = NotchSummary(sessions: [waiting("a")], now: Date(timeIntervalSince1970: 1_060))
        #expect(CollapsedNotch(summary: summary, setup: prompt(nothing)) == .needsYou(count: 1, longestWait: 60))
    }

    @Test func aConnectedAgentHidesTheSetupWings() {
        #expect(!prompt(with([.claudeCode: .installed])).showsWings)
        // A partly installed agent means the user has been here: no hint, but the card says so.
        #expect(!prompt(with([.codex: .partial])).showsWings)
        // Every agent disconnected again: the hint is back.
        #expect(prompt(nothing).showsWings)
    }

    // The owner replaced the two-step "Not now" (a week, then for good) on 2026-11-26: "Later" only
    // ever means a week, and the permanent no is Skip, per agent.
    @Test func laterHidesSetupForAWeekEachTime() {
        func shown(_ dismissal: SetupDismissal, after: TimeInterval) -> SetupPrompt {
            SetupPrompt(
                ownsSocket: true, dismissal: dismissal, now: start.addingTimeInterval(after),
                found: [.claudeCode, .codex], statuses: nothing)
        }
        let never = SetupDismissal()
        #expect(shown(never, after: 0).showsWings)
        #expect(shown(never, after: 0).closeTitle == "Later")
        #expect(shown(never, after: 0).closeHint == "Hides setup for a week")

        // Put off: hidden for seven days, then back as before.
        let once = never.closed(at: start)
        #expect(!shown(once, after: 0).showsWings)
        #expect(!shown(once, after: 7 * day - 1).showsCard)
        #expect(shown(once, after: 7 * day).showsWings)
        #expect(shown(once, after: 7 * day).showsCard)
        #expect(shown(once, after: 7 * day).closeTitle == "Later")

        // Put off again: another week, never for good.
        let twice = once.closed(at: start.addingTimeInterval(8 * day))
        #expect(!shown(twice, after: 8 * day).showsWings)
        #expect(!shown(twice, after: 15 * day - 1).showsCard)
        #expect(shown(twice, after: 15 * day).showsWings)
        #expect(SetupDismissal.snooze == 7 * day)
    }

    @Test func skippingEveryAgentEndsTheHint() {
        // One agent skipped: the other is still offered, so the hint stays.
        let one = prompt(nothing, skipped: [.codex])
        #expect(one.showsWings)
        #expect(one.rows.map(\.agent) == [.claudeCode])
        // Every agent found on this Mac skipped: a clear no, though none is connected.
        let all = prompt(nothing, skipped: [.claudeCode, .codex])
        #expect(!all.showsWings)
        #expect(!all.showsCard)
        // The same for the two agents offered when none is found.
        #expect(!prompt(found: [], nothing, skipped: [.claudeCode, .codex]).showsWings)
        #expect(prompt(found: [], nothing, skipped: [.codex]).rows.map(\.agent) == [.claudeCode])
    }

    @Test func setupPutOffStaysHiddenWhateverElseChanges() {
        let p = prompt(dismissed: true, nothing)
        #expect(!p.showsWings)
        #expect(!p.showsCard)
        // Also after an install made in this run, and when hooks are removed later.
        #expect(!prompt(dismissed: true, with([.codex: .installed]), installedNow: [.codex]).showsCard)
    }

    @Test func aCopyWithoutTheSocketOffersNoSetup() {
        let p = prompt(ownsSocket: false, nothing)
        #expect(!p.showsWings)
        #expect(!p.showsCard)
    }

    // MARK: The card (UI-17)

    @Test func theCardListsTheAgentsFoundOnThisMacInAFixedOrder() {
        let p = prompt(found: [.antigravity, .codex, .claudeCode], nothing)
        #expect(p.rows.map(\.agent) == [.claudeCode, .codex, .antigravity])
        let codex = p.rows[1]
        #expect(codex.detail == "~/.codex/hooks.json")
        #expect(codex.action == .connect)
        #expect(p.closeTitle == "Later")
        // An agent that shows up later is listed the next time the card is built.
        #expect(prompt(found: [.claudeCode, .codex, .cursor, .antigravity], nothing).rows.map(\.agent)
            == [.claudeCode, .codex, .cursor, .antigravity])
        // Hooks that are installed count as found, whatever the folders say.
        #expect(prompt(found: [.claudeCode], with([.openCode: .installed])).rows.map(\.agent) == [.claudeCode, .openCode])
    }

    @Test func aSkippedAgentLeavesTheListAndCanBeBroughtBack() {
        let found: Set<AgentKind> = [.claudeCode, .codex, .cursor, .antigravity]
        let p = prompt(found: found, nothing, skipped: [.cursor, .antigravity])
        #expect(p.rows.map(\.agent) == [.claudeCode, .codex])
        // The skipped ones are named, in the fixed order, so each can be undone.
        #expect(p.skipped == [.cursor, .antigravity])
        // Every row that is not installed can be skipped; an installed one cannot.
        let mixed = prompt(found: found, with([.claudeCode: .installed, .codex: .partial]))
        #expect(mixed.rows.map(\.canSkip) == [false, true, true, true])
        // A skip for an agent that is not on this Mac is not listed: there is nothing to bring back.
        #expect(prompt(nothing, skipped: [.openCode]).skipped.isEmpty)
        // Undo is the same list without that agent.
        #expect(prompt(found: found, nothing, skipped: [.antigravity]).rows.map(\.agent) == [.claudeCode, .codex, .cursor])
    }

    @Test func aSkippedAgentThatIsInstalledAnywayIsShownAsInstalled() {
        // Installed from Settings after being skipped: it counts as connected, and is not listed as skipped.
        let p = prompt(with([.codex: .installed]), skipped: [.codex])
        #expect(!p.showsWings)
        #expect(p.rows.map(\.agent) == [.claudeCode, .codex])
        #expect(p.rows[1].detail == "Hooks installed")
        #expect(p.skipped.isEmpty)
        // A partly installed agent that is skipped stays out of the list, and still counts as connected for the hint.
        let partial = prompt(with([.codex: .partial]), skipped: [.codex])
        #expect(partial.rows.map(\.agent) == [.claudeCode])
        #expect(partial.skipped == [.codex])
        #expect(!partial.showsWings)
    }

    @Test func withNoAgentFoundClaudeCodeAndCodexAreOffered() {
        #expect(prompt(found: [], nothing).rows.map(\.agent) == [.claudeCode, .codex])
    }

    @Test func theCardStaysForAgentsStillToConnect() {
        let p = prompt(with([.claudeCode: .installed]))
        #expect(!p.showsWings)
        #expect(p.rows.map(\.agent) == [.claudeCode, .codex])
        #expect(p.rows[0].detail == "Hooks installed")
        #expect(p.rows[0].action == nil)
        // Installed before this launch: nothing more to say about it.
        #expect(p.rows[0].nextStep == nil)
        #expect(p.rows[1].action == .connect)
        #expect(p.closeTitle == "Later")
    }

    @Test func anInstallMadeNowKeepsTheCardAndSaysWhatToDoNext() {
        // The last install must not take its own next step away.
        let p = prompt(with([.claudeCode: .installed, .codex: .installed]), installedNow: [.codex])
        #expect(p.showsCard)
        #expect(p.closeTitle == "Done")
        let codex = p.rows[1]
        #expect(codex.nextStep == "Next: trust the hooks in Codex. Use Review hooks in the app, or /hooks in the CLI.")
        #expect(p.rows[0].nextStep == nil)

        let all = prompt(
            found: Set(AgentKind.allCases),
            Dictionary(uniqueKeysWithValues: AgentKind.allCases.map { ($0, HookInstallStatus.installed) }),
            installedNow: Set(AgentKind.allCases))
        #expect(all.rows.map(\.nextStep) == [
            "Restart sessions that were already running.",
            "Next: trust the hooks in Codex. Use Review hooks in the app, or /hooks in the CLI.",
            nil,
            "Restart OpenCode to load the plugin.",
            "Restart sessions that were already running.",
        ])
        #expect(all.rows[3].detail == "Plugin installed")
    }

    @Test func everythingInstalledEarlierShowsNoCard() {
        let p = prompt(with([.claudeCode: .installed, .codex: .installed]))
        #expect(!p.showsCard)
        #expect(p.rows.isEmpty)
        #expect(!p.showsWings)
    }

    @Test func partlyInstalledAndUnreadableFilesAreShownAsTheyAre() {
        // No entry for Codex: its file could not be read.
        var statuses = with([.claudeCode: .partial])
        statuses[.codex] = nil
        let p = prompt(statuses)
        #expect(p.rows[0].detail == "Partly installed")
        #expect(p.rows[0].action == .repair)
        #expect(p.rows[1].detail == "Could not read its file. See Settings.")
        #expect(p.rows[1].action == nil)
        #expect(p.rows[1].status == nil)
        #expect(p.closeTitle == "Later")
        // An unreadable file alone does not count as connected.
        var unread = nothing
        unread[.codex] = nil
        #expect(prompt(unread).showsWings)
    }

    @Test func theConfirmationNamesTheFileAndPromisesABackupOnlyForAnExistingFile() {
        // What you get, which file changes, what is sent and where, and the way back (ONB-01).
        // The backup is promised only before a change: a repair can find nothing to change.
        #expect(SetupPrompt.confirmation(for: .claudeCode, fileExists: true)
            == "To show Claude Code sessions here, Who's Working adds a hook to ~/.claude/settings.json, backing it up before any change. "
            + "Claude Code then passes its events, prompts, commands and paths included, to Who's Working on this Mac. "
            + "Uninstall in Settings removes it.")
        // A new file has nothing to back up, so no backup is promised.
        #expect(SetupPrompt.confirmation(for: .codex, fileExists: false)
            == "To show Codex sessions here, Who's Working creates ~/.codex/hooks.json with a hook in it. "
            + "Codex then passes its events, prompts, commands and paths included, to Who's Working on this Mac. "
            + "Uninstall in Settings removes it.")
        #expect(SetupPrompt.confirmation(for: .openCode, fileExists: false)
            == "To show OpenCode sessions here, Who's Working adds its own plugin file, ~/.config/opencode/plugins/whoisworking.js. "
            + "The plugin sends status, commands and paths to Who's Working on this Mac, not your prompts. "
            + "Uninstall in Settings deletes it.")
        // Any copy that differs from this version is backed up before it is replaced.
        #expect(SetupPrompt.confirmation(for: .openCode, fileExists: true)
            == "To show OpenCode sessions here, Who's Working replaces its own plugin file, ~/.config/opencode/plugins/whoisworking.js, and backs up the old copy first. "
            + "The plugin sends status, commands and paths to Who's Working on this Mac, not your prompts. "
            + "Uninstall in Settings deletes it.")
        // Settings' alert says where the sessions show.
        #expect(SetupPrompt.confirmation(for: .codex, fileExists: false, place: "in the notch")
            .hasPrefix("To show Codex sessions in the notch, "))
    }

    @Test func theConfirmationSaysWhatEachAgentsEventsHold() {
        // Taken from the payloads each agent sends (Tests/Fixtures): Antigravity's PreInvocation holds
        // the prompt, Cursor's afterAgentThought the agent's thinking.
        #expect(SetupPrompt.confirmation(for: .antigravity, fileExists: true).contains("passes its events, prompts, commands and paths included,"))
        #expect(SetupPrompt.confirmation(for: .cursor, fileExists: true).contains("passes its events, commands, paths and the agent's thinking included,"))
        for agent in AgentKind.allCases {
            for exists in [true, false] {
                let text = SetupPrompt.confirmation(for: agent, fileExists: exists)
                #expect(text.contains("on this Mac"))
                #expect(!text.contains("events in"), "event counts stay out of the visible text")
                #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"))
                // The card's row has room for about 40 words (whoisworking-copy skill).
                #expect(text.split(separator: " ").count <= 42, "\(agent) \(exists): \(text.split(separator: " ").count) words")
            }
        }
    }

    @Test func settingsExplainsTheChangeWhatIsSentAndTheWayBackInFull() {
        // ONB-02: Settings has room for every fact the card leaves out. It shows before the file
        // exists, so the backup is conditional, and a file Who's Working created stays after uninstall.
        #expect(SetupPrompt.settingsExplanation(for: .codex)
            == "To show Codex sessions in the notch, Who's Working adds a hook to ~/.codex/hooks.json. "
            + "Before it changes an existing file, it backs the file up. "
            + "Codex then passes its events, prompts, commands and paths included, to Who's Working. "
            + "These events stay on this Mac, and the hook never approves, blocks or changes anything. "
            + "Uninstall removes only Who's Working's entries. Your other hooks, the backups and a file it created stay.")
        #expect(SetupPrompt.settingsExplanation(for: .openCode)
            == "To show OpenCode sessions in the notch, Who's Working adds its own plugin file, ~/.config/opencode/plugins/whoisworking.js. "
            + "Before it replaces an older copy, it backs that copy up. "
            + "The plugin passes OpenCode's status, commands and paths to Who's Working, not the prompts you type. "
            + "These events stay on this Mac, and the plugin never answers a permission or changes anything. "
            + "Uninstall deletes only that file, with a backup if you edited it. Other plugins stay as they are.")
        for agent in AgentKind.allCases {
            let sentences = SetupPrompt.settingsExplanation(for: agent).split(separator: ". ")
            #expect(sentences.allSatisfy { $0.split(separator: " ").count <= 25 }, "plain-language sentence length")
            // The app as a whole does use the network (Check for Updates), so only the events are said to stay.
            #expect(!SetupPrompt.settingsExplanation(for: agent).contains("Nothing leaves"))
        }
    }

    @Test func theConfirmButtonNamesWhatItAdds() {
        #expect(SetupPrompt.confirmTitle(for: .claudeCode) == "Add hook")
        #expect(SetupPrompt.confirmTitle(for: .openCode) == "Add plugin")
    }

    @Test func onlyAnInstallThatChangedTheFileAndLeftItInstalledCountsAsMadeNow() {
        #expect(SetupPrompt.countsAsInstalledNow(changed: true, status: .installed))
        // Antigravity keeps hooks the user turned off: a repair can change nothing and stay partial.
        #expect(!SetupPrompt.countsAsInstalledNow(changed: false, status: .partial))
        #expect(!SetupPrompt.countsAsInstalledNow(changed: true, status: .partial))
        #expect(!SetupPrompt.countsAsInstalledNow(changed: false, status: .installed))
        #expect(!SetupPrompt.countsAsInstalledNow(changed: true, status: nil))
        #expect(SetupPrompt.stillPartialNote(for: .antigravity)
            == "Still partly installed. If the Who's Working hooks are turned off in Antigravity, turn them on there.")
    }

    @Test func agentsAreFoundByTheirConfigFolders() {
        let home = URL(fileURLWithPath: "/Users/someone")
        let present: Set<String> = ["/Users/someone/.claude", "/Users/someone/.config/opencode", "/Users/someone/.gemini"]
        let found = SetupPrompt.agentsFound(home: home) { present.contains($0.path) }
        #expect(found == [.claudeCode, .openCode, .antigravity])
        #expect(SetupPrompt.agentsFound(home: home) { _ in false }.isEmpty)
    }

    @Test func aFileWithAnAgentFoldersNameIsNotAFolder() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("setup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try "not a folder".write(to: home.appendingPathComponent(".cursor"), atomically: true, encoding: .utf8)
        #expect(SetupPrompt.agentsFound(home: home) == [.claudeCode])
    }
}
