import Foundation
import Testing
@testable import AgentCore

// OpenCode v2 (spec 12). Real payloads come from Tests/Fixtures/opencode-real: `runN.jsonl` holds the
// captured events (the plugin's input), `runN.forwarded.jsonl` what the plugin sends (the adapter's input).

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func message(_ body: [String: Any]) throws -> Data {
    var data = Data("whoisworking1 opencode ppid=4242\n".utf8)
    data.append(try JSONSerialization.data(withJSONObject: body))
    return data
}

private func event(_ body: [String: Any]) throws -> AgentEvent? {
    try HookMessage.parse(message(body)).flatMap { $0.event(receivedAt: now) }
}

private func lines(_ name: String) throws -> [String] {
    String(decoding: try fixture("opencode-real/\(name)"), as: UTF8.self)
        .split(separator: "\n").map(String.init)
}

private func shortTempDir() throws -> URL {
    let url = URL(fileURLWithPath: "/tmp/wiw-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: - Adapter

@Suite("OpenCode adapter")
struct OpenCodeAdapterTests {
    private func body(_ type: String, _ data: [String: Any], created: Double = 1_795_357_000_000, note: [String: Any] = [:])
        -> [String: Any]
    {
        ["type": type, "created": created, "data": data, "whoisworking": note]
    }

    @Test func lifecycleAndExecutionMapToSessionEvents() throws {
        #expect(try event(body("session.created", ["sessionID": "ses_a"]))?.kind == .sessionStarted)
        #expect(try event(body("session.deleted", ["sessionID": "ses_a"]))?.kind == .sessionEnded)
        #expect(try event(body("session.renamed", ["sessionID": "ses_a", "title": "Fix login"]))?.kind == .renamed)
        #expect(try event(body("session.execution.started", ["sessionID": "ses_a"]))?.kind == .promptSubmitted)
        #expect(try event(body("session.execution.succeeded", ["sessionID": "ses_a"]))?.kind == .stopped(lastMessage: nil))
        let failed = body("session.execution.failed", ["sessionID": "ses_a", "error": ["type": "api", "message": "Rate limited"]])
        #expect(try event(failed)?.kind == .failed(error: "Rate limited"))
        let bare = body("session.execution.failed", ["sessionID": "ses_a"])
        #expect(try event(bare)?.kind == .failed(error: "OpenCode run failed"))
        let user = body("session.execution.interrupted", ["sessionID": "ses_a", "reason": "user"])
        #expect(try event(user)?.kind == .interrupted)
        #expect(try event(body("session.created", ["sessionID": "ses_a"]))?.agent == .openCode)
    }

    @Test func supersededInterruptionsAreDropped() throws {
        let superseded = body("session.execution.interrupted", ["sessionID": "ses_a", "reason": "superseded"])
        #expect(try event(superseded) == nil)
        let shutdown = body("session.execution.interrupted", ["sessionID": "ses_a", "reason": "shutdown"])
        #expect(try event(shutdown)?.kind == .interrupted)
    }

    @Test func toolsStepsAndFormsMap() throws {
        let shell = body("session.tool.called", [
            "sessionID": "ses_a", "id": "call_1", "name": "shell", "input": ["command": "swift test"],
        ])
        #expect(try event(shell)?.kind
            == .toolStarted(ToolActivity(name: "shell", summary: "swift test", detail: "swift test"), subagent: false))
        let read = body("session.tool.called", ["sessionID": "ses_a", "id": "call_2", "name": "read", "input": ["path": "/p/App.swift"]])
        #expect(try event(read)?.kind
            == .toolStarted(ToolActivity(name: "read", summary: "Reading App.swift", detail: "/p/App.swift"), subagent: false))
        #expect(try event(body("session.step.started", ["sessionID": "ses_a"]))?.kind == .activity(nil))
        let form = body("form.created", ["form": ["id": "frm_1", "sessionID": "ses_a", "title": "Which database?"]])
        let formEvent = try #require(try event(form))
        #expect(formEvent.sessionId == "ses_a")
        #expect(formEvent.kind == .waitingForReply(message: "Which database?"))
    }

    @Test func theEventTimeIsTheEventDate() throws {
        let e = try #require(try event(body("session.execution.started", ["sessionID": "ses_a"], created: 1_795_357_005_475)))
        #expect(e.date == Date(timeIntervalSince1970: 1_795_357_005.475))
        let undated: [String: Any] = ["type": "session.execution.started", "data": ["sessionID": "ses_a"]]
        #expect(try event(undated)?.date == now)
    }

    @Test func unknownOrBrokenInputIsDropped() throws {
        #expect(try event(body("session.usage.updated", ["sessionID": "ses_a"])) == nil)
        #expect(try event(body("session.execution.started", [:])) == nil)
        #expect(OpenCodeAdapter.event(from: Data("{".utf8), receivedAt: now) == nil)
        #expect(OpenCodeAdapter.event(from: Data("[]".utf8), receivedAt: now) == nil)
    }

    @Test func folderAndNameComeFromTheEventOrTheLookup() throws {
        var withLocation = body("session.step.started", ["sessionID": "ses_a"], note: ["directory": "/Users/me/other"])
        withLocation["location"] = ["directory": "/Users/me/dev/demo"]
        #expect(try event(withLocation)?.cwd == "/Users/me/dev/demo")
        let fromLookup = body("session.execution.started", ["sessionID": "ses_a"], note: ["directory": "/Users/me/dev/demo", "title": "Fix login"])
        let e = try #require(try event(fromLookup))
        #expect(e.cwd == "/Users/me/dev/demo")
        #expect(e.name == "Fix login")
        #expect(try event(body("session.execution.started", ["sessionID": "ses_a"]))?.cwd == nil)
    }

    @Test func permissionsCarryTheirRequestId() throws {
        let asked = body("permission.asked", [
            "id": "per_1", "sessionID": "ses_a", "action": "external_directory", "resources": ["/etc/*"],
        ])
        guard case .permissionRequested(let tool)? = try event(asked)?.kind else {
            Issue.record("permission.asked did not map"); return
        }
        #expect(tool.requestId == "per_1")
        #expect(tool.name == "external_directory")
        #expect(tool.detail == "/etc/*")
        #expect(tool.summary == "External directory: /etc/*")
        let replied = body("permission.replied", ["sessionID": "ses_a", "requestID": "per_1", "reply": "once"])
        #expect(try event(replied)?.kind == .permissionReplied(requestId: "per_1"))
    }

    @Test func childSessionsActOnTheirRoot() throws {
        let note: [String: Any] = ["parentID": "ses_mid", "rootID": "ses_root"]
        let created = body("session.created", ["sessionID": "ses_child", "parentID": "ses_mid", "agent": "general"], note: note)
        let c = try #require(try event(created))
        #expect(c.sessionId == "ses_root")
        #expect(c.kind == .subagent(started: true, type: "general"))
        let asked = body("permission.asked", ["id": "per_9", "sessionID": "ses_child", "action": "bash", "resources": ["rm -rf build"]], note: note)
        #expect(try event(asked)?.sessionId == "ses_root")
        let replied = body("permission.replied", ["sessionID": "ses_child", "requestID": "per_9", "reply": "reject"], note: note)
        #expect(try event(replied)?.kind == .permissionReplied(requestId: "per_9"))
        let tool = body("session.tool.called", ["sessionID": "ses_child", "id": "call_9", "name": "shell", "input": ["command": "ls"]], note: note)
        let t = try #require(try event(tool))
        #expect(t.sessionId == "ses_root")
        #expect(t.kind == .toolStarted(ToolActivity(name: "shell", summary: "ls", detail: "ls"), subagent: true))
        for type in ["session.execution.started", "session.execution.succeeded", "session.deleted"] {
            #expect(try event(body(type, ["sessionID": "ses_child"], note: note)) == nil, "\(type) from a child")
        }
        // A child's model step means the root is working again, for example after the user answered
        // the child's question (changed after review: this used to be dropped).
        let step = try #require(try event(body("session.step.started", ["sessionID": "ses_child"], note: note)))
        #expect(step.sessionId == "ses_root")
        #expect(step.kind == .activity(nil))
        // A child known only from its own session.created event (no lookup yet) is still a subagent.
        let bareChild = body("session.created", ["sessionID": "ses_x", "parentID": "ses_root", "agent": "general"])
        #expect(try event(bareChild)?.sessionId == "ses_root")
    }

    @Test func deletedSessionsAreRemoved() throws {
        let start = try #require(try event(body("session.execution.started", ["sessionID": "ses_a"])))
        let end = try #require(try event(body("session.deleted", ["sessionID": "ses_a"], created: 1_795_357_001_000)))
        let state = [start, end].reduce(SessionsState()) { reduce($0, .agent($1)) }
        #expect(state.sessions["ses_a"] == nil)
        #expect(start.pid == nil)
    }

    @Test func routesOpenCodeMessagesToTheAdapter() throws {
        let e = try #require(try event(body("session.execution.started", ["sessionID": "ses_a"])))
        #expect(e.agent == .openCode)
        #expect(HookMessage.parse(try message(body("session.execution.started", ["sessionID": "ses_a"])))?.parentPid == 4242)
    }
}

// MARK: - Real payloads

@Suite("OpenCode real payloads")
struct OpenCodeRealPayloadTests {
    /// Each forwarded message with the event it maps to. A subagent's own execution and step messages
    /// map to nothing on purpose (OPC-05).
    private func mapped(_ run: String) throws -> [(body: [String: Any], event: AgentEvent?)] {
        try lines("\(run).forwarded.jsonl").map { line in
            var data = Data("whoisworking1 opencode ppid=4242\n".utf8)
            data.append(Data(line.utf8))
            let body = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            return (body, HookMessage.parse(data)?.event(receivedAt: now))
        }
    }

    private func forwarded(_ run: String) throws -> [AgentEvent] { try mapped(run).compactMap(\.event) }

    @Test func mapsEveryCapturedEvent() throws {
        let actOnTheRoot: Set = [
            "session.created", "session.tool.called", "session.step.started", "permission.asked", "permission.replied",
            "form.created",
        ]
        for run in ["run1", "run2", "run3", "run4", "e2e-permission"] {
            for (body, event) in try mapped(run) {
                let isChild = (body["whoisworking"] as? [String: Any])?["parentID"] != nil
                let type = body["type"] as? String ?? ""
                if !isChild || actOnTheRoot.contains(type) {
                    #expect(event != nil, "\(run): \(type) did not map")
                } else {
                    #expect(event == nil, "\(run): a subagent's \(type) must not change a row")
                }
            }
        }
    }

    @Test func capturedRunsEndInTheRightState() throws {
        func final(_ run: String) throws -> SessionsState {
            try forwarded(run).reduce(SessionsState()) { reduce($0, .agent($1)) }
        }
        // A plain reply and a shell command end done.
        for run in ["run1", "run2"] {
            let state = try final(run)
            #expect(state.sessions.count == 1)
            #expect(state.sessions.values.first?.state == .doneUnseen)
            #expect(state.sessions.values.first?.cwd == "/Users/me/dev/demo")
        }
        // The rejected permission: needs approval first, then the interrupted run leaves it idle.
        let run3 = try forwarded("run3")
        let asking = run3.prefix { if case .permissionReplied = $0.kind { false } else { true } }
            .reduce(SessionsState()) { reduce($0, .agent($1)) }
        #expect(asking.sessions.values.first?.state == .needsApproval)
        #expect(asking.sessions.values.first?.pendingTool?.detail == "/etc/*")
        #expect(try final("run3").sessions.values.first?.state == .idle)
        // The subagent never becomes a row; the parent ends done.
        let run4 = try final("run4")
        #expect(run4.sessions.count == 1)
        #expect(run4.sessions.values.first?.state == .doneUnseen)
    }

    @Test func thePluginInsideOpenCodeEndsTheRejectedRunIdle() throws {
        // Sent by the shipped plugin while loaded by OpenCode 2.0.14 itself, not by a test harness.
        let run = try forwarded("e2e-permission")
        let asking = run.prefix { if case .permissionReplied = $0.kind { false } else { true } }
            .reduce(SessionsState()) { reduce($0, .agent($1)) }
        #expect(asking.sessions.values.first?.state == .needsApproval)
        #expect(asking.sessions.values.first?.pendingTool?.requestId == "per_e2epermission1")
        let end = run.reduce(SessionsState()) { reduce($0, .agent($1)) }
        #expect(end.sessions.count == 1)
        #expect(end.sessions.values.first?.state == .idle)
        #expect(end.sessions.values.first?.cwd == "/Users/me/dev/demo")
    }
}

// MARK: - Plugin installer

@Suite("OpenCode plugin installer")
struct OpenCodePluginInstallerTests {
    private func temp() throws -> (URL, PluginInstaller) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wiw-plugin-\(UUID().uuidString)")
        let file = dir.appendingPathComponent("plugins/whoisworking.js")
        return (file, PluginInstaller(fileURL: file, now: { Date(timeIntervalSince1970: 1_800_000_000) }))
    }

    private func backups(_ file: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)) ?? [])
            .filter { $0.hasPrefix("whoisworking.js.whoisworking-backup-") }
    }

    @Test func installWritesThePluginAndIsIdempotent() throws {
        let (file, installer) = try temp()
        #expect(try installer.install().changed)
        #expect(try String(contentsOf: file, encoding: .utf8) == OpenCodePlugin.contents)
        #expect(OpenCodePlugin.contents.hasPrefix(OpenCodePlugin.marker))
        #expect(!(try installer.install().changed))
        #expect(backups(file).isEmpty)
    }

    @Test func refusesAFileItDidNotWrite() throws {
        let (file, installer) = try temp()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let mine = "export default { id: \"mine\", setup() {} }\n"
        try Data(mine.utf8).write(to: file)
        #expect(throws: HookInstallerError.self) { try installer.install() }
        #expect(throws: HookInstallerError.self) { try installer.uninstall() }
        #expect(throws: HookInstallerError.self) { try installer.status() }
        #expect(try String(contentsOf: file, encoding: .utf8) == mine)
    }

    @Test func replacingAnEditedCopyKeepsABackup() throws {
        let (file, installer) = try temp()
        try installer.install()
        let edited = OpenCodePlugin.contents + "// my tweak\n"
        try Data(edited.utf8).write(to: file)
        #expect(try installer.status() == .partial)
        #expect(try installer.install().changed)
        #expect(try String(contentsOf: file, encoding: .utf8) == OpenCodePlugin.contents)
        let saved = try #require(backups(file).first)
        let backup = file.deletingLastPathComponent().appendingPathComponent(saved)
        #expect(try String(contentsOf: backup, encoding: .utf8) == edited)
    }

    @Test func uninstallRemovesOnlyItsOwnFile() throws {
        let (file, installer) = try temp()
        try installer.install()
        let other = file.deletingLastPathComponent().appendingPathComponent("orca-status.js")
        try Data("// other\n".utf8).write(to: other)
        #expect(try installer.uninstall().changed)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
        #expect(!(try installer.uninstall().changed))
    }

    @Test func uninstallRemovesALinkNotItsTarget() throws {
        // A plugin linked in from a dotfiles checkout: uninstall removes the link and keeps the checkout.
        let (file, installer) = try temp()
        let dotfiles = file.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("dotfiles.js")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(OpenCodePlugin.contents.utf8).write(to: dotfiles)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: dotfiles)
        #expect(try installer.uninstall().changed)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: file.path)) == nil)
        #expect(FileManager.default.fileExists(atPath: dotfiles.path))
    }

    @Test func removingAnEditedCopyKeepsABackup() throws {
        let (file, installer) = try temp()
        try installer.install()
        let edited = OpenCodePlugin.contents + "// my tweak\n"
        try Data(edited.utf8).write(to: file)
        let result = try installer.uninstall()
        let backup = try #require(result.backupURL)
        #expect(try String(contentsOf: backup, encoding: .utf8) == edited)
    }

    @Test func updateReplacesOnlyAnOutdatedOwnedFile() throws {
        let (file, installer) = try temp()
        #expect(!(try installer.updateIfOutdated()))  // nothing installed: nothing to update
        #expect(!FileManager.default.fileExists(atPath: file.path))
        try installer.install()
        #expect(!(try installer.updateIfOutdated()))  // current
        try Data((OpenCodePlugin.marker + " old version\n").utf8).write(to: file)
        #expect(try installer.updateIfOutdated())
        #expect(try String(contentsOf: file, encoding: .utf8) == OpenCodePlugin.contents)
        #expect(backups(file).count == 1)
        // A linked copy is left alone: updating it would write into someone's checkout.
        let elsewhere = file.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("linked.js")
        try Data((OpenCodePlugin.marker + " old version\n").utf8).write(to: elsewhere)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: elsewhere)
        #expect(!(try installer.updateIfOutdated()))
        #expect(try String(contentsOf: elsewhere, encoding: .utf8) == OpenCodePlugin.marker + " old version\n")
    }

    @Test func statusFollowsTheFile() throws {
        let (_, installer) = try temp()
        #expect(try installer.status() == .notInstalled)
        try installer.install()
        #expect(try installer.status() == .installed)
        #expect(try installer.preview(.uninstall).after.isEmpty)
    }
}

// MARK: - Plugin behaviour (runs the JavaScript under Node when it is installed)

private let nodeAvailable: Bool = {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = ["node", "--version"]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
}()

/// How the fake WhoIsWorking and OpenCode behave around the plugin.
private struct HarnessOptions: Encodable {
    /// A listener stands in for WhoIsWorking; false means the app is not running.
    var listen = true
    /// The listener reads the first message but never closes that connection.
    var stallFirst = false
    /// Calls the plugin's cleanup after this many milliseconds instead of when messages stop arriving.
    var cleanupAfterMs: Int? = nil
    /// `ctx.session.get` fails the first time it is asked about these sessions.
    var failFirstLookupFor: [String] = []
    /// Lets Node exit by itself after cleanup, to see whether the plugin keeps it alive.
    var exitNaturally = false
}

private struct HarnessResult {
    var received: [String]
    /// Milliseconds between cleanup and the Node process exiting.
    var exitAfterCleanupMs: Double
}

/// Runs the plugin against scripted events and a fake `ctx`, with a Unix socket listener standing in for
/// WhoIsWorking. Returns the raw messages the listener received, in order.
private func runPlugin(events: [String], sessions: String = "{}", options: HarnessOptions = HarnessOptions()) throws
    -> HarnessResult
{
    let dir = try shortTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let plugin = dir.appendingPathComponent("whoisworking.mjs")
    try Data(OpenCodePlugin.contents.utf8).write(to: plugin)
    try Data(events.joined(separator: "\n").utf8).write(to: dir.appendingPathComponent("events.jsonl"))
    try Data(sessions.utf8).write(to: dir.appendingPathComponent("sessions.json"))
    try JSONEncoder().encode(options).write(to: dir.appendingPathComponent("options.json"))
    let harness = #"""
    import { createServer } from "node:net";
    import { readFileSync, writeFileSync } from "node:fs";
    const [dir] = process.argv.slice(2);
    const events = readFileSync(dir + "/events.jsonl", "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
    const sessions = JSON.parse(readFileSync(dir + "/sessions.json", "utf8"));
    const options = JSON.parse(readFileSync(dir + "/options.json", "utf8"));
    const received = [];
    let server, connections = 0;
    if (options.listen) {
      server = createServer({ allowHalfOpen: true }, (c) => {
        const stall = options.stallFirst && connections++ === 0;
        let b = "";
        c.on("data", (d) => (b += d));
        c.on("end", () => { received.push(b); if (!stall) c.end(); });
        c.on("error", () => {});
      });
      await new Promise((r) => server.listen(dir + "/s.sock", r));
    }
    const failing = new Set(options.failFirstLookupFor);
    const plugin = (await import(dir + "/whoisworking.mjs")).default;
    const ctx = {
      event: { subscribe: ({ signal }) => (async function* () {
        for (const e of events) yield e;
        await new Promise((r) => signal.addEventListener("abort", r));
      })() },
      session: { get: async ({ sessionID }) => {
        if (failing.delete(sessionID)) throw new Error("lookup failed");
        return sessions[sessionID] ?? {};
      } },
    };
    const started = Date.now();
    const cleanup = plugin.setup(ctx);
    if (options.cleanupAfterMs != null) {
      await new Promise((r) => setTimeout(r, options.cleanupAfterMs));
    } else {
      let last = -1, stableSince = Date.now();
      while (Date.now() - started < 4000) {
        await new Promise((r) => setTimeout(r, 50));
        if (received.length !== last) { last = received.length; stableSince = Date.now(); }
        else if (Date.now() - stableSince > 400) break;
      }
    }
    cleanup();
    server?.close();
    await new Promise((r) => setTimeout(r, 100));
    writeFileSync(dir + "/result.json", JSON.stringify({ id: plugin.id, received, cleanupAt: Date.now() }));
    if (!options.exitNaturally) process.exit(0);
    """#
    try Data(harness.utf8).write(to: dir.appendingPathComponent("harness.mjs"))
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = ["node", dir.appendingPathComponent("harness.mjs").path, dir.path]
    // The plugin reads WhoIsWorking's socket path from its environment.
    var env = ProcessInfo.processInfo.environment
    env["WHOISWORKING_SOCKET"] = dir.appendingPathComponent("s.sock").path
    p.environment = env
    try p.run()
    p.waitUntilExit()
    let exited = Date().timeIntervalSince1970 * 1000
    let data = try Data(contentsOf: dir.appendingPathComponent("result.json"))
    let result = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(result["id"] as? String == "whoisworking")
    let cleanupAt = (result["cleanupAt"] as? NSNumber)?.doubleValue ?? exited
    return HarnessResult(received: result["received"] as? [String] ?? [], exitAfterCleanupMs: exited - cleanupAt)
}

/// Synthetic `session.step.started` events, numbered by their `created` time.
private func steps(_ count: Int, session: String = "ses_a") -> [String] {
    (1 ... count).map { #"{"type":"session.step.started","created":\#($0),"data":{"sessionID":"\#(session)"}}"# }
}

private func bodies(_ messages: [String]) throws -> [[String: Any]] {
    try messages.map { m in
        let parts = m.split(separator: "\n", maxSplits: 1).map(String.init)
        #expect(parts.first?.hasPrefix("whoisworking1 opencode ppid=") == true)
        return try #require(try JSONSerialization.jsonObject(with: Data(parts[1].utf8)) as? [String: Any])
    }
}

// In CI these run even without node, so a missing node fails the build instead of skipping silently.
@Suite("OpenCode plugin", .enabled(if: nodeAvailable || ProcessInfo.processInfo.environment["CI"] != nil, "needs node on PATH"))
struct OpenCodePluginTests {
    @Test func forwardsTrimmedEventsInOrder() throws {
        // The plugin turns each run's captured events into exactly its forwarded fixture.
        for run in ["run1", "run2", "run3", "run4"] {
            let sessions = String(decoding: try fixture("opencode-real/sessions.json"), as: UTF8.self)
            let got = try bodies(runPlugin(events: lines("\(run).jsonl"), sessions: sessions).received)
            let want = try lines("\(run).forwarded.jsonl").map {
                try JSONSerialization.jsonObject(with: Data($0.utf8)) as? NSDictionary
            }
            #expect(got.map { $0 as NSDictionary } == want.compactMap { $0 }, "\(run)")
        }
        let shell = try bodies(runPlugin(events: lines("run2.jsonl")).received)
            .first { $0["type"] as? String == "session.tool.called" }
        let data = try #require(shell?["data"] as? [String: Any])
        #expect(data["name"] as? String == "shell")
        #expect(data["input"] as? [String: String] == ["command": "echo hello"])
    }

    @Test func childSessionsCarryTheirRoot() throws {
        let sessions = String(decoding: try fixture("opencode-real/sessions.json"), as: UTF8.self)
        let got = try bodies(runPlugin(events: lines("run4.jsonl"), sessions: sessions).received)
        let created = try #require(got.first { $0["type"] as? String == "session.created" })
        let note = try #require(created["whoisworking"] as? [String: Any])
        #expect(note["rootID"] as? String == "ses_session4")
        #expect(note["parentID"] as? String == "ses_session4")
        // The tool call that started the subagent sends no prompt text.
        let task = try #require(got.first { $0["type"] as? String == "session.tool.called" })
        let input = try #require((task["data"] as? [String: Any])?["input"] as? [String: Any])
        #expect(input["prompt"] == nil)
    }

    @Test func doesNothingWhenTheAppIsNotRunning() throws {
        var options = HarnessOptions()
        options.listen = false
        options.exitNaturally = true
        let result = try runPlugin(events: lines("run2.jsonl"), options: options)
        #expect(result.received.isEmpty)
        #expect(result.exitAfterCleanupMs < 500)
    }

    @Test func aStalledAppCostsOneSecondAndTheQueueKeepsTheNewest() throws {
        // The first send hangs; while it waits, 299 more events arrive and only the newest 256 are kept.
        var options = HarnessOptions()
        options.stallFirst = true
        options.cleanupAfterMs = 2500  // past the 1 s send timeout and the drain that follows
        let got = try bodies(runPlugin(events: steps(300), options: options).received)
        let times = got.compactMap { ($0["created"] as? NSNumber)?.intValue }
        #expect(times.count == 257)
        #expect(times.first == 1)
        #expect(Array(times.dropFirst()) == Array(45 ... 300))
    }

    @Test func cleanupStopsSending() throws {
        var options = HarnessOptions()
        options.stallFirst = true
        options.cleanupAfterMs = 300
        options.exitNaturally = true
        let result = try runPlugin(events: steps(300), options: options)
        #expect(result.received.count <= 1, "received \(result.received.count)")
        // Nothing the plugin started (sockets, timers) keeps OpenCode from exiting.
        #expect(result.exitAfterCleanupMs < 500)
    }

    @Test func aFailedLookupIsTriedAgain() throws {
        // The first lookup for the child fails; the next event for it still finds its parent.
        var options = HarnessOptions()
        options.failFirstLookupFor = ["ses_child"]
        let sessions = #"{"ses_child": {"id": "ses_child", "parentID": "ses_root"}, "ses_root": {"id": "ses_root"}}"#
        let events = [
            #"{"type":"session.step.started","created":1,"data":{"sessionID":"ses_child"}}"#,
            #"{"type":"session.step.started","created":2,"data":{"sessionID":"ses_child"}}"#,
        ]
        let got = try bodies(runPlugin(events: events, sessions: sessions, options: options).received)
        let roots = got.map { ($0["whoisworking"] as? [String: Any])?["rootID"] as? String }
        #expect(roots.last == "ses_root")
    }
}

@Suite("OpenCode plugin source")
struct OpenCodePluginSourceTests {
    @Test func onlyObservesAndUsesOnlyBuiltIns() {
        let source = OpenCodePlugin.contents
        let imports = source.split(separator: "\n").filter { $0.hasPrefix("import ") }
        #expect(!imports.isEmpty)
        for line in imports { #expect(line.contains("\"node:"), "\(line)") }
        for forbidden in ["permission.hook", ".reply(", "tool.execute", "transform", "process.exit", "console."] {
            #expect(!source.contains(forbidden), "\(forbidden)")
        }
    }
}
