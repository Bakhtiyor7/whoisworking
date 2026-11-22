import Darwin
import Foundation

// MARK: - Paths

public enum AppPaths {
    public static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WhoIsWorking", isDirectory: true)
    }

    public static var socket: URL { supportDirectory.appendingPathComponent("events.sock") }
    public static var hookScript: URL { supportDirectory.appendingPathComponent("whoisworking-hook") }
    public static var eventLog: URL { supportDirectory.appendingPathComponent("event-log", isDirectory: true) }

    /// The command written into agent settings. `$HOME` keeps it free of the user name.
    public static func hookCommand(agent: String) -> String {
        #""$HOME/Library/Application Support/WhoIsWorking/whoisworking-hook" "# + agent
    }

    public static var claudeSettings: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    public static var claudeSessions: URL {
        // Debug override, used to show the empty state.
        if let dir = ProcessInfo.processInfo.environment["WHOISWORKING_CLAUDE_SESSIONS"] { return URL(fileURLWithPath: dir) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions", isDirectory: true)
    }
}

// MARK: - Socket server

/// Listens on a Unix socket; each connection carries one message (read until EOF).
/// The parent directory is made owner-only (0700) and the socket 0600.
public final class EventSocketServer: @unchecked Sendable {
    public enum Failure: Error, Equatable { case alreadyRunning, pathTooLong, system(String) }

    public static let maxMessageBytes = 1 << 20
    public static let readTimeoutSeconds = 2

    private let path: String
    private let onMessage: @Sendable (Data) -> Void
    private let queue = DispatchQueue(label: "whoisworking.socket.accept")
    private let workers = DispatchQueue(label: "whoisworking.socket.read", attributes: .concurrent)
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?

    public init(path: String, onMessage: @escaping @Sendable (Data) -> Void) {
        self.path = path
        self.onMessage = onMessage
    }

    deinit { stop() }

    public func start() throws {
        guard path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else { throw Failure.pathTooLong }

        let dir = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir)
        } catch {
            throw Failure.system("cannot prepare \(dir): \(error.localizedDescription)")
        }

        if FileManager.default.fileExists(atPath: path) {
            if Self.canConnect(path) { throw Failure.alreadyRunning }
            unlink(path)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.system("socket: \(String(cString: strerror(errno)))") }
        var addr = Self.address(path)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw Failure.system("bind: \(message)")
        }
        chmod(path, 0o600)
        guard listen(fd, 64) == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            unlink(path)
            throw Failure.system("listen: \(message)")
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        listenFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.setCancelHandler { close(fd) }
        self.source = source
        source.resume()
    }

    public func stop() {
        guard let source else { return }
        self.source = nil
        source.cancel()
        listenFD = -1
        unlink(path)
    }

    private func acceptPending() {
        while true {
            let client = accept(listenFD, nil, nil)
            guard client >= 0 else { return }
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            var timeout = timeval(tv_sec: Self.readTimeoutSeconds, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            let handler = onMessage
            workers.async {
                let data = Self.readAll(client)
                // Handle before closing: the hook (and its parent processes) waits until we close,
                // so the handler can still walk its process chain.
                if !data.isEmpty { handler(data) }
                close(client)
            }
        }
    }

    private static func readAll(_ fd: Int32) -> Data {
        // Accepted sockets inherit O_NONBLOCK from the listener on Darwin; reads should block (with timeout).
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while data.count < maxMessageBytes {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }

    private static func address(_ path: String) -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            path.utf8CString.withUnsafeBytes { src in
                buf.copyMemory(from: UnsafeRawBufferPointer(rebasing: src.prefix(buf.count - 1)))
            }
        }
        return addr
    }

    private static func canConnect(_ path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = address(path)
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        } == 0
    }
}

// MARK: - Hook script

/// The script agents run for every hook event. Uses only `/bin/sh` and `/usr/bin/nc`, which macOS ships.
public enum HookScript {
    public static let contents = #"""
    #!/bin/sh
    # WhoIsWorking hook. Installed and removed by the WhoIsWorking app; safe to delete.
    # Forwards the agent's hook JSON (stdin) to WhoIsWorking's socket and exits 0.
    # Prints nothing, never makes a decision, and does nothing when WhoIsWorking is not running.
    # ppid lets WhoIsWorking find the agent process (for cleanup and "Open session").
    SOCK="${WHOISWORKING_SOCKET:-$HOME/Library/Application Support/WhoIsWorking/events.sock}"
    AGENT="${1:-claude-code}"
    if [ -S "$SOCK" ]; then
      { printf 'whoisworking1 %s ppid=%s\n' "$AGENT" "$PPID"; cat; } | /usr/bin/nc -U -w 1 "$SOCK" >/dev/null 2>&1
    else
      cat >/dev/null 2>&1
    fi
    exit 0

    """#

    public static func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// Deletes the script unless some agent's default hook file still has WhoIsWorking's hooks.
    public static func removeIfUnused(at url: URL, defaultSettings: (HookTarget) -> URL = { $0.defaultSettingsURL }) {
        let stillUsed = HookTarget.all.contains { t in
            let installer = HookInstaller(
                target: t, settingsURL: defaultSettings(t), hookCommand: AppPaths.hookCommand(agent: t.id))
            return ((try? installer.status()) ?? .notInstalled) != .notInstalled
        }
        if !stillUsed { try? FileManager.default.removeItem(at: url) }
    }

    /// True when the installed script matches this version.
    public static func isCurrent(at url: URL) -> Bool {
        (try? String(contentsOf: url, encoding: .utf8)) == contents
    }
}

// MARK: - Discovery

/// Reads `~/.claude/sessions/*.json`.
public struct ClaudeSessionScanner: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func scan() -> [DiscoveredSession] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { (try? Data(contentsOf: $0)).flatMap(ClaudeSessionFile.parse) }
    }
}

/// Process checks. Injectable for tests.
public struct ProcessProbe: Sendable {
    /// A process that started more than this after the session did is a reused pid.
    public static let startTolerance: TimeInterval = 5

    private let startTime: @Sendable (Int32) -> Date?
    private let parentLookup: @Sendable (Int32) -> Int32?
    private let nameLookup: @Sendable (Int32) -> String?
    private let argumentsLookup: @Sendable (Int32) -> [String]?
    private let allPidsLookup: @Sendable () -> [Int32]
    private let cwdLookup: @Sendable (Int32) -> String?
    private let terminalLookup: @Sendable (Int32) -> Bool

    public init(
        startTime: @escaping @Sendable (Int32) -> Date?,
        parent: @escaping @Sendable (Int32) -> Int32? = { _ in nil },
        name: @escaping @Sendable (Int32) -> String? = { _ in nil },
        arguments: @escaping @Sendable (Int32) -> [String]? = { _ in nil },
        allPids: @escaping @Sendable () -> [Int32] = { [] },
        cwd: @escaping @Sendable (Int32) -> String? = { _ in nil },
        hasTerminal: @escaping @Sendable (Int32) -> Bool = { _ in false }
    ) {
        self.startTime = startTime
        self.parentLookup = parent
        self.nameLookup = name
        self.argumentsLookup = arguments
        self.allPidsLookup = allPids
        self.cwdLookup = cwd
        self.terminalLookup = hasTerminal
    }

    /// The process has a controlling terminal (interactive CLIs do; helpers started by apps do not).
    public func hasTerminal(_ pid: Int32) -> Bool { terminalLookup(pid) }

    public func allPids() -> [Int32] { allPidsLookup() }
    public func cwd(of pid: Int32) -> String? { cwdLookup(pid) }
    public func startTime(of pid: Int32) -> Date? { startTime(pid) }

    public func name(of pid: Int32) -> String? { nameLookup(pid) }
    public func arguments(of pid: Int32) -> [String]? { argumentsLookup(pid) }

    /// `pid` itself or its nearest ancestor whose process name is `named`.
    public func ancestor(of pid: Int32, named: String) -> Int32? {
        var current: Int32? = pid
        var steps = 0
        while let p = current, p > 1, steps < 32 {
            if name(of: p) == named { return p }
            current = parent(of: p)
            steps += 1
        }
        return nil
    }

    public static let system = ProcessProbe(
        startTime: { pid in kinfo(pid).map { info in
            let tv = info.kp_proc.p_starttime
            return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000)
        } },
        parent: { pid in kinfo(pid).map { $0.kp_eproc.e_ppid } },
        name: { pid in
            kinfo(pid).map { info in
                withUnsafeBytes(of: info.kp_proc.p_comm) { raw in
                    String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                }
            }
        },
        arguments: { pid in processArguments(pid) },
        allPids: {
            let count = proc_listallpids(nil, 0)
            guard count > 0 else { return [] }
            var pids = [Int32](repeating: 0, count: Int(count) + 64)
            let n = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
            return n > 0 ? Array(pids.prefix(Int(n))).filter { $0 > 0 } : []
        },
        cwd: { pid in
            var info = proc_vnodepathinfo()
            let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
            return withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
        },
        hasTerminal: { pid in
            guard let info = kinfo(pid) else { return false }
            return info.kp_eproc.e_tdev != -1 && (info.kp_proc.p_flag & P_CONTROLT) != 0
        }
    )

    /// argv of a process via KERN_PROCARGS2 (only works for the current user's processes).
    private static func processArguments(_ pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }  // executable path
        while index < size, buffer[index] == 0 { index += 1 }  // padding
        var args: [String] = []
        while args.count < argc, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            args.append(String(decoding: buffer[start ..< index], as: UTF8.self))
            index += 1
        }
        return args
    }

    /// The process exists and, when `startedAt` is known, is not a later process that reused the pid.
    public func isAlive(_ pid: Int32, startedAt: Date?) -> Bool {
        guard pid > 0, let started = startTime(pid) else { return false }
        guard let startedAt else { return true }
        return started <= startedAt.addingTimeInterval(Self.startTolerance)
    }

    public func parent(of pid: Int32) -> Int32? { parentLookup(pid) }

    private static func kinfo(_ pid: Int32) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == pid else {
            return nil
        }
        return info
    }
}

/// Turns a scan into store events: live files become `discovered`, known pids that died become `processExited`.
/// Files whose process is gone (left behind by a crash) are ignored.
public func discoveryEvents(
    known: [Session], found: [DiscoveredSession], now: Date, isAlive: (Int32, Date?) -> Bool
) -> [StoreEvent] {
    var events: [StoreEvent] = []
    var alivePids: Set<Int32> = []
    var startedAtByPid: [Int32: Date] = [:]
    for file in found {
        if let s = file.startedAt { startedAtByPid[file.pid] = s }
        if isAlive(file.pid, file.startedAt) {
            alivePids.insert(file.pid)
            events.append(.discovered(file, at: now))
        }
    }
    var exited: [Int32] = []
    for session in known.sorted(by: { $0.id < $1.id }) {
        guard let pid = session.pid, !alivePids.contains(pid), !exited.contains(pid) else { continue }
        if !isAlive(pid, startedAtByPid[pid]) { exited.append(pid) }
    }
    events += exited.map { .processExited(pid: $0) }
    return events
}
