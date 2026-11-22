import Darwin
import Foundation
import Testing
@testable import AgentCore

/// Short temp dir: Unix socket paths are limited to 104 bytes.
private func shortTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("p-\(UUID().uuidString.prefix(8))")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private final class Inbox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Data] = []
    func add(_ d: Data) { lock.lock(); items.append(d); lock.unlock() }
    var all: [Data] { lock.lock(); defer { lock.unlock() }; return items }

    /// Polls up to `timeout` seconds for `count` messages.
    func wait(for count: Int, timeout: TimeInterval = 3) async -> [Data] {
        let deadline = Date().addingTimeInterval(timeout)
        while all.count < count, Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        return all
    }
}

private func send(_ data: Data, to path: String) throws {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    defer { close(fd) }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &addr.sun_path) { buf in
        _ = path.utf8CString.withUnsafeBytes { src in memcpy(buf.baseAddress!, src.baseAddress!, src.count) }
    }
    let ok = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard ok == 0 else { throw POSIXError(.ECONNREFUSED) }
    _ = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
    shutdown(fd, SHUT_WR)
    var byte: UInt8 = 0
    _ = read(fd, &byte, 1)  // wait for the server to close
}

/// Runs the hook script with `stdin`, returns (exit code, stdout+stderr, seconds).
private func runHook(
    _ script: URL, stdin: String, socket: String, arguments: [String] = ["claude-code"]
) throws -> (Int32, String, TimeInterval) {
    let p = Process()
    p.executableURL = script
    p.arguments = arguments
    p.environment = ["WHOISWORKING_SOCKET": socket, "PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()]
    let input = Pipe(), output = Pipe()
    p.standardInput = input
    p.standardOutput = output
    p.standardError = output
    let start = Date()
    try p.run()
    input.fileHandleForWriting.write(Data(stdin.utf8))
    try input.fileHandleForWriting.close()
    p.waitUntilExit()
    let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return (p.terminationStatus, text, Date().timeIntervalSince(start))
}

private func mode(_ path: String) throws -> Int {
    try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as! Int
}

@Suite("Event socket", .serialized)
struct EventSocketTests {
    @Test func receivesOneMessagePerConnectionWithOwnerOnlyPermissions() async throws {
        let dir = try shortTempDir().appendingPathComponent("WhoIsWorking")
        let path = dir.appendingPathComponent("events.sock").path
        let inbox = Inbox()
        let server = EventSocketServer(path: path) { inbox.add($0) }
        try server.start()
        defer { server.stop() }

        #expect(try mode(dir.path) == 0o700)
        #expect(try mode(path) == 0o600)

        try send(Data(#"{"n":1}"#.utf8), to: path)
        try send(Data(#"{"n":2}"#.utf8), to: path)
        let got = await inbox.wait(for: 2)
        #expect(Set(got.map { String(decoding: $0, as: UTF8.self) }) == [#"{"n":1}"#, #"{"n":2}"#])
    }

    @Test func replacesAStaleSocketFile() async throws {
        let dir = try shortTempDir()
        let path = dir.appendingPathComponent("events.sock").path
        FileManager.default.createFile(atPath: path, contents: Data("stale".utf8))
        let inbox = Inbox()
        let server = EventSocketServer(path: path) { inbox.add($0) }
        try server.start()
        defer { server.stop() }
        try send(Data("{}".utf8), to: path)
        #expect(await inbox.wait(for: 1).count == 1)
    }

    @Test func refusesToStartWhenAnotherServerIsListening() throws {
        let dir = try shortTempDir()
        let path = dir.appendingPathComponent("events.sock").path
        let first = EventSocketServer(path: path) { _ in }
        try first.start()
        defer { first.stop() }
        let second = EventSocketServer(path: path) { _ in }
        #expect(throws: EventSocketServer.Failure.alreadyRunning) { try second.start() }
    }

    /// The handler must run while the hook is still connected, so the hook's parent processes still exist.
    @Test func theHandlerRunsBeforeTheConnectionCloses() async throws {
        let dir = try shortTempDir()
        let path = dir.appendingPathComponent("events.sock").path
        let server = EventSocketServer(path: path) { _ in Thread.sleep(forTimeInterval: 0.3) }
        try server.start()
        defer { server.stop() }
        let start = Date()
        try send(Data("{}".utf8), to: path)  // returns when the server closes the connection
        #expect(Date().timeIntervalSince(start) >= 0.29)
    }

    @Test func stopRemovesTheSocket() throws {
        let dir = try shortTempDir()
        let path = dir.appendingPathComponent("events.sock").path
        let server = EventSocketServer(path: path) { _ in }
        try server.start()
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
    }
}

@Suite("Hook script", .serialized)
struct HookScriptTests {
    private func installScript() throws -> URL {
        let url = try shortTempDir().appendingPathComponent("whoisworking-hook")
        try HookScript.write(to: url)
        return url
    }

    @Test func isExecutableAndOnlyUsesSystemTools() throws {
        let url = try installScript()
        #expect(try mode(url.path) == 0o755)
        #expect(HookScript.contents.hasPrefix("#!/bin/sh\n"))
        #expect(HookScript.contents.contains("/usr/bin/nc"))
    }

    @Test func exitsZeroQuicklyAndSilentlyWhenTheAppIsNotRunning() throws {
        let script = try installScript()
        let missing = try shortTempDir().appendingPathComponent("none.sock").path
        let (code, output, seconds) = try runHook(script, stdin: #"{"session_id":"x"}"#, socket: missing)
        #expect(code == 0)
        #expect(output.isEmpty)
        #expect(seconds < 0.5)
    }

    @Test func exitsZeroWhenTheSocketFileIsStale() throws {
        let script = try installScript()
        let stale = try shortTempDir().appendingPathComponent("events.sock")
        // A real socket file with no listener behind it, like after a crash.
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            _ = stale.path.utf8CString.withUnsafeBytes { memcpy(buf.baseAddress!, $0.baseAddress!, $0.count) }
        }
        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        close(fd)
        let (code, output, seconds) = try runHook(script, stdin: "{}", socket: stale.path)
        #expect(code == 0)
        #expect(output.isEmpty)
        #expect(seconds < 1.5)
    }

    @Test func forwardsStdinWithAnAgentHeader() async throws {
        let script = try installScript()
        let path = try shortTempDir().appendingPathComponent("events.sock").path
        let inbox = Inbox()
        let server = EventSocketServer(path: path) { inbox.add($0) }
        try server.start()
        defer { server.stop() }

        let payload = #"{"session_id":"abc","hook_event_name":"Stop"}"#
        let (code, output, seconds) = try runHook(script, stdin: payload, socket: path)
        #expect(code == 0)
        #expect(output.isEmpty)
        #expect(seconds < 1.0)
        let got = await inbox.wait(for: 1)
        // The header names the agent and the hook's parent pid (here: this test process, which ran the script).
        #expect(got.first.map { String(decoding: $0, as: UTF8.self) } == "whoisworking1 claude-code ppid=\(getpid())\n" + payload)
        #expect(got.first.flatMap { HookMessage.parse($0)?.parentPid } == getpid())
        #expect(got.first.flatMap { HookMessage.parse($0)?.event(receivedAt: Date()) }?.kind == .stopped(lastMessage: nil))
    }

    @Test func forwardsTheEventNameWhenGiven() async throws {
        let script = try installScript()
        let path = try shortTempDir().appendingPathComponent("events.sock").path
        let inbox = Inbox()
        let server = EventSocketServer(path: path) { inbox.add($0) }
        try server.start()
        defer { server.stop() }

        let payload = #"{"conversationId":"c1","fullyIdle":true}"#
        let (code, output, _) = try runHook(script, stdin: payload, socket: path, arguments: ["antigravity", "Stop"])
        #expect(code == 0)
        #expect(output.isEmpty)
        let got = await inbox.wait(for: 1)
        #expect(got.first.map { String(decoding: $0, as: UTF8.self) } == "whoisworking1 antigravity ppid=\(getpid()) event=Stop\n" + payload)
        #expect(got.first.flatMap { HookMessage.parse($0)?.eventName } == "Stop")
    }

    @Test func malformedEventArgumentsAreLeftOut() async throws {
        let script = try installScript()
        let path = try shortTempDir().appendingPathComponent("events.sock").path
        let inbox = Inbox()
        let server = EventSocketServer(path: path) { inbox.add($0) }
        try server.start()
        defer { server.stop() }
        for bad in ["Stop extra", "Stop;rm", ""] {
            let (code, output, _) = try runHook(script, stdin: "{}", socket: path, arguments: ["antigravity", bad])
            #expect(code == 0)
            #expect(output.isEmpty)
        }
        let got = await inbox.wait(for: 3)
        for message in got {
            #expect(String(decoding: message, as: UTF8.self) == "whoisworking1 antigravity ppid=\(getpid())\n{}")
        }
    }

    @Test func exitsZeroSilentlyWithAnEventNameAndNoApp() throws {
        let script = try installScript()
        let missing = try shortTempDir().appendingPathComponent("none.sock").path
        let (code, output, seconds) = try runHook(script, stdin: "{}", socket: missing, arguments: ["antigravity", "Stop"])
        #expect(code == 0)
        #expect(output.isEmpty)
        #expect(seconds < 0.5)
    }
}

@Suite("Discovery")
struct DiscoveryTests {
    @Test func scansSessionFilesAndSkipsBrokenOnes() throws {
        let dir = try shortTempDir()
        try fixture("claude-sessions/53992.json").write(to: dir.appendingPathComponent("53992.json"))
        try Data("{broken".utf8).write(to: dir.appendingPathComponent("1.json"))
        try Data("ignored".utf8).write(to: dir.appendingPathComponent("53992.abc.key"))
        let found = ClaudeSessionScanner(directory: dir).scan()
        #expect(found.map(\.pid) == [53992])
    }

    @Test func missingDirectoryScansAsEmpty() {
        let found = ClaudeSessionScanner(directory: URL(fileURLWithPath: "/nonexistent-\(UUID())")).scan()
        #expect(found.isEmpty)
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func liveSessionsAreReportedAndDeadPidsRemoved() {
        let known = [
            Session(id: "old", state: .working, stateSince: now, pid: 10),
            Session(id: "alive", state: .working, stateSince: now, pid: 20),
            Session(id: "hook-only", state: .working, stateSince: now),
        ]
        let found = [
            DiscoveredSession(sessionId: "alive", pid: 20, status: "busy"),
            DiscoveredSession(sessionId: "new", pid: 30, status: "idle"),
            DiscoveredSession(sessionId: "stale-file", pid: 40, status: "busy"),
        ]
        let alive: Set<Int32> = [20, 30]
        let events = discoveryEvents(known: known, found: found, now: now) { pid, _ in alive.contains(pid) }
        #expect(events == [
            .discovered(found[0], at: now),
            .discovered(found[1], at: now),
            .processExited(pid: 10),
        ])
    }

    @Test func aReusedPidDoesNotCountAsAlive() {
        // Process 20 exists but started after the session did: the pid was reused.
        let started = now.addingTimeInterval(-600)
        let found = [DiscoveredSession(sessionId: "s", pid: 20, status: "busy", startedAt: started)]
        let probe = ProcessProbe(startTime: { _ in started.addingTimeInterval(300) })
        #expect(!probe.isAlive(20, startedAt: started))
        let ok = ProcessProbe(startTime: { _ in started.addingTimeInterval(-0.5) })
        #expect(ok.isAlive(20, startedAt: started))
        #expect(ProcessProbe(startTime: { _ in nil }).isAlive(20, startedAt: started) == false)
        _ = found
    }

    @Test func theRealProbeSeesThisProcess() {
        let me = getpid()
        #expect(ProcessProbe.system.isAlive(me, startedAt: Date()))
        #expect(!ProcessProbe.system.isAlive(me, startedAt: Date().addingTimeInterval(-86_400 * 365)))
        #expect(ProcessProbe.system.parent(of: me) == getppid())
    }
}
