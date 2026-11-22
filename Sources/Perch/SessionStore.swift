import AgentCore
import AppKit
import Foundation

/// Owns the session list and feeds it from the socket and from discovery.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var state = SessionsState() {
        didSet { dumpState() }
    }
    /// Ticks once a second so elapsed times stay current.
    @Published private(set) var now = Date()
    @Published private(set) var socketError: String?

    private var server: EventSocketServer?
    private var discoveryTimer: Timer?
    private var clockTimer: Timer?
    private var directoryWatcher: DispatchSourceFileSystemObject?
    private var watchedFD: Int32 = -1
    private let scanner = ClaudeSessionScanner(directory: PerchPaths.claudeSessions)
    private let probe = ProcessProbe.system
    private let logEvents: Bool

    init() {
        logEvents = ProcessInfo.processInfo.environment["PERCH_LOG_EVENTS"] == "1"
            || UserDefaults.standard.bool(forKey: "logEvents")
    }

    var summary: NotchSummary { NotchSummary(sessions: state.sessions.values, now: now) }

    func start() {
        startSocket()
        rescan()
        watchSessionsDirectory()
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rescan() }
        }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Sockets survive sleep, but re-check everything: sessions may have ended while asleep.
                if self.server == nil { self.startSocket() }
                self.rescan()
            }
        }
    }

    func stop() {
        server?.stop()
        directoryWatcher?.cancel()
    }

    func apply(_ event: StoreEvent) {
        let next = reduce(state, event)
        if next != state { state = next }
    }

    /// `PERCH_DEBUG_STATE=/path/file.txt` writes a readable snapshot on every change (for checks without screenshots).
    private let debugStatePath = ProcessInfo.processInfo.environment["PERCH_DEBUG_STATE"]

    private func dumpState() {
        guard let debugStatePath else { return }
        let s = NotchSummary(sessions: state.sessions.values, now: Date())
        var lines = ["updated \(ISO8601DateFormatter().string(from: Date()))",
                     "wings: \(s.showsWings ? "\(s.needsYouCount) need you, longest wait \(formatElapsed(s.longestWait ?? 0))" : "hidden")"]
        for (title, list) in [("NEEDS YOU", s.needsYou), ("WORKING", s.working), ("DONE", s.done)] where !list.isEmpty {
            lines.append(title)
            for x in list {
                lines.append("  [\(x.agent.shortCode)] \(x.displayName) | \(x.state.rawValue) | \(x.rowDetail) | \(formatElapsed(Date().timeIntervalSince(x.stateSince))) | pid \(x.pid.map(String.init) ?? "-") | hooks \(x.hasHookEvents)")
                if x.state == .needsApproval { lines.append("    request: \(x.requestTitle) :: \(x.requestDetail ?? "")") }
            }
        }
        try? (lines.joined(separator: "\n") + "\n").write(toFile: debugStatePath, atomically: true, encoding: .utf8)
    }

    func markViewed(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        apply(.viewed(ids: ids, at: Date()))
    }

    // MARK: Socket

    private func startSocket() {
        let logEvents = self.logEvents
        let probe = self.probe
        let server = EventSocketServer(path: PerchPaths.socket.path) { [weak self] data in
            // Runs on the socket thread while the hook is still connected, so its parent chain still exists.
            let received = Date()
            if logEvents { EventLog.write(data, at: received) }
            guard let message = HookMessage.parse(data), var event = message.event(receivedAt: received) else { return }
            if event.agent == .codex, let parent = message.parentPid {
                event.pid = CodexProcesses.owningProcess(ofHookParent: parent, probe: probe)
            }
            Task { @MainActor in self?.receive(event) }
        }
        do {
            try server.start()
            self.server = server
            socketError = nil
        } catch EventSocketServer.Failure.alreadyRunning {
            socketError = "Another copy of Perch is already running."
        } catch {
            socketError = "Could not listen for agent events: \(error)"
        }
    }

    private func receive(_ event: AgentEvent) {
        apply(.agent(event))
        // A new session id usually means a new session file: pick up its pid and name now.
        if state.sessions[event.sessionId]?.pid == nil { rescan() }
    }

    // MARK: Discovery

    func rescan() {
        let found = scanner.scan()
        let probe = self.probe
        let events = discoveryEvents(known: Array(state.sessions.values), found: found, now: Date()) {
            probe.isAlive($0, startedAt: $1)
        }
        // Codex has no session files: running interactive CLIs show as placeholders until their first hook.
        let codexProcesses = CodexProcesses.discoveryEvents(probe: probe, now: Date())
        // Codex fires no hook when a turn fails: a quiet "working" Codex session gets its rollout read.
        let endedTurns = state.sessions.values.compactMap {
            CodexRollout.endOfQuietTurn($0, now: Date()) { CodexRollout.readTail(of: $0) }
        }
        var next = state
        for event in events + codexProcesses + endedTurns + [.pruneOrphans(now: Date())] { next = reduce(next, event) }
        if next != state { state = next }
    }

    private func watchSessionsDirectory() {
        let path = PerchPaths.claudeSessions.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }  // No directory yet; the timer still rescans.
        watchedFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.rescan() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        directoryWatcher = source
    }
}

/// Optional raw event capture for building test fixtures (`PERCH_LOG_EVENTS=1`).
enum EventLog {
    static func write(_ data: Data, at date: Date) {
        let dir = PerchPaths.eventLog
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        let payload = HookMessage.parse(data)?.payload ?? data
        let name = (try? JSONSerialization.jsonObject(with: payload) as? [String: Any])?["hook_event_name"] as? String ?? "unknown"
        let stamp = String(format: "%.3f", date.timeIntervalSince1970)
        try? payload.write(to: dir.appendingPathComponent("\(stamp)-\(name).json"))
    }
}
