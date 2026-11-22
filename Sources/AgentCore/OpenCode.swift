import Foundation

// OpenCode v2 (spec 12): a plugin file WhoIsWorking owns, its installer, and the adapter for what it sends.

// MARK: - Plugin source

/// The plugin WhoIsWorking installs into `~/.config/opencode/plugins/`. OpenCode v2 loads it into its server.
public enum OpenCodePlugin {
    /// First line of the file; a file at the plugin path without it is not WhoIsWorking's.
    public static let marker = "// WhoIsWorking OpenCode plugin."

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode/plugins/whoisworking.js")
    }

    public static let contents = #"""
    // WhoIsWorking OpenCode plugin. Installed and removed by the WhoIsWorking app; safe to delete.
    // Forwards session status (working, waiting for you, done) to WhoIsWorking's local socket.
    // It only observes: it never answers a permission or a form, never changes input or output,
    // never sends prompt, file or tool output text, and does nothing when WhoIsWorking is not running.
    import { createConnection } from "node:net";
    import { statSync } from "node:fs";
    import { homedir } from "node:os";
    import { join } from "node:path";

    const SOCKET = process.env.WHOISWORKING_SOCKET
      || join(homedir(), "Library", "Application Support", "WhoIsWorking", "events.sock");
    const MAX_QUEUE = 256;
    const SEND_TIMEOUT_MS = 1000;
    const LOOKUP_TIMEOUT_MS = 1000;
    const FORWARDED = new Set([
      "session.created", "session.renamed", "session.deleted",
      "session.execution.started", "session.execution.succeeded",
      "session.execution.failed", "session.execution.interrupted",
      "session.step.started", "session.tool.called",
      "permission.asked", "permission.replied", "form.created",
    ]);
    const INPUT_KEYS = ["command", "path", "filePath", "pattern", "url", "description", "agent"];

    const text = (value, max = 1000) => (typeof value === "string" ? value.slice(0, max) : undefined);

    function socketReady() {
      try { return statSync(SOCKET).isSocket(); } catch { return false; }
    }

    // Only the fields WhoIsWorking reads.
    function trim(type, d, toolNames) {
      switch (type) {
        case "session.created":
          return {
            sessionID: d.sessionID, parentID: d.parentID, agent: text(d.agent, 100), title: text(d.title, 200),
            location: d.location?.directory ? { directory: d.location.directory } : undefined,
          };
        case "session.renamed":
          return { sessionID: d.sessionID, title: text(d.title, 200) };
        case "session.execution.failed":
          return {
            sessionID: d.sessionID,
            error: d.error ? { type: text(d.error.type, 100), message: text(d.error.message, 500) } : undefined,
          };
        case "session.execution.interrupted":
          return { sessionID: d.sessionID, reason: text(d.reason, 50) };
        case "session.tool.called": {
          const input = {};
          for (const key of INPUT_KEYS) {
            const value = text(d.input?.[key]);
            if (value !== undefined) input[key] = value;
          }
          return { sessionID: d.sessionID, id: d.id, name: toolNames.get(d.id), input };
        }
        case "permission.asked":
          return {
            id: d.id, sessionID: d.sessionID, action: text(d.action, 200),
            resources: Array.isArray(d.resources) ? d.resources.slice(0, 20).map((r) => text(String(r))) : [],
          };
        case "permission.replied":
          return { sessionID: d.sessionID, requestID: d.requestID, reply: text(d.reply, 20) };
        case "form.created":
          return { form: { id: d.form?.id, sessionID: d.form?.sessionID, title: text(d.form?.title, 500) } };
        default:
          return { sessionID: d.sessionID };
      }
    }

    export default {
      id: "whoisworking",
      setup(ctx) {
        const controller = new AbortController();
        const sessions = new Map(); // sessionID -> Promise<{ parentID, directory, title }>
        const toolNames = new Map(); // tool call id -> tool name
        const queue = [];
        let pumping = false;
        let stopped = false;
        let finishSend; // ends the send in flight, if any

        // One message per connection. Resolves once WhoIsWorking has read it and closed, or after a timeout.
        const send = (line) => new Promise((resolve) => {
          let finished = false;
          let socket;
          const timer = setTimeout(() => done(), SEND_TIMEOUT_MS);
          timer.unref?.();
          function done() {
            if (finished) return;
            finished = true;
            finishSend = undefined;
            clearTimeout(timer);
            try { socket?.destroy(); } catch {}
            resolve();
          }
          finishSend = done;
          try {
            socket = createConnection(SOCKET);
            socket.on("error", done);
            socket.on("close", done);
            socket.on("connect", () => socket.end(line));
          } catch { done(); }
        });

        // Facts about a session from OpenCode. A failed or slow lookup is not remembered: the next
        // event for that session asks again, so a subagent is not mistaken for a top-level session for good.
        const lookup = (id) => {
          const known = sessions.get(id);
          if (known) return known;
          let timer;
          const timeout = new Promise((resolve) => {
            timer = setTimeout(() => resolve(undefined), LOOKUP_TIMEOUT_MS);
            timer.unref?.();
          });
          const forget = () => { if (sessions.get(id) === result) sessions.delete(id); return {}; };
          const result = Promise.race([Promise.resolve().then(() => ctx.session.get({ sessionID: id })), timeout])
            .then((info) => info
              ? { parentID: info.parentID, directory: info.location?.directory, title: info.title }
              : forget())
            .catch(forget)
            .finally(() => clearTimeout(timer));
          sessions.set(id, result);
          return result;
        };

        // The top-level session a subagent belongs to: the one the user sees.
        const rootOf = async (id) => {
          let current = id;
          for (let depth = 0; depth < 8; depth++) {
            const info = await lookup(current);
            if (!info.parentID) return current;
            current = info.parentID;
          }
          return current;
        };

        const build = async (draft) => {
          // WhoIsWorking is not running: no lookups, nothing to send.
          if (!socketReady()) return undefined;
          const info = await lookup(draft.sessionID);
          const note = {};
          if (info.parentID) {
            note.parentID = info.parentID;
            note.rootID = await rootOf(draft.sessionID);
          }
          const directory = draft.directory ?? info.directory;
          if (directory) note.directory = directory;
          if (info.title) note.title = text(info.title, 200);
          const message = { type: draft.type, created: draft.created, data: draft.data, whoisworking: note };
          if (draft.seq !== undefined) message.seq = draft.seq;
          return `whoisworking1 opencode ppid=${process.pid}\n${JSON.stringify(message)}`;
        };

        // Sends in order, one at a time, so WhoIsWorking sees events in the order OpenCode emitted them.
        const pump = async () => {
          if (pumping) return;
          pumping = true;
          try {
            while (queue.length > 0 && !stopped) {
              const job = queue.shift();
              let line;
              try { line = await job(); } catch { line = undefined; }
              if (line && !stopped) await send(line);
            }
          } finally {
            pumping = false;
          }
        };

        const enqueue = (job) => {
          if (stopped) return;
          if (queue.length >= MAX_QUEUE) queue.shift();
          queue.push(job);
          void pump();
        };

        const observe = (event) => {
          const d = event?.data ?? {};
          switch (event?.type) {
            case "session.created":
              if (typeof d.sessionID === "string") {
                sessions.set(d.sessionID, Promise.resolve({
                  parentID: d.parentID, directory: d.location?.directory, title: d.title,
                }));
              }
              break;
            case "session.renamed": {
              // Only a session already looked up takes the title here; otherwise its lookup brings it.
              const before = sessions.get(d.sessionID);
              if (before) sessions.set(d.sessionID, before.then((info) => ({ ...info, title: d.title })));
              break;
            }
            case "session.tool.input.started":
              if (d.id && d.name) {
                toolNames.set(d.id, d.name);
                if (toolNames.size > 1024) toolNames.delete(toolNames.keys().next().value);
              }
              return;
          }
          if (!FORWARDED.has(event?.type)) return;
          const sessionID = event.type === "form.created" ? d.form?.sessionID : d.sessionID;
          if (typeof sessionID !== "string") return;
          // Trimmed now, so the queue never holds prompt text, file contents or tool output.
          const draft = {
            type: event.type, created: event.created, sessionID, data: trim(event.type, d, toolNames),
            directory: event.location?.directory,
            seq: typeof event.durable?.seq === "number" ? event.durable.seq : undefined,
          };
          enqueue(() => build(draft));
          if (event.type === "session.deleted") {
            enqueue(async () => { sessions.delete(sessionID); return undefined; });
          }
        };

        void (async () => {
          try {
            for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
              try { observe(event); } catch {}
            }
          } catch {}
        })();

        return () => {
          stopped = true;
          queue.length = 0;
          controller.abort();
          finishSend?.();
        };
      },
    };

    """#
}

// MARK: - Installer

/// Installs and removes the plugin file WhoIsWorking owns (OPC-01). It never touches another file:
/// a file at the path without `OpenCodePlugin.marker` is refused, and a marked copy that differs
/// from this version is backed up before it is replaced or removed.
public struct PluginInstaller: Sendable {
    public let fileURL: URL
    public let contents: String
    public let now: @Sendable () -> Date

    public init(
        fileURL: URL = OpenCodePlugin.defaultURL, contents: String = OpenCodePlugin.contents,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileURL = fileURL
        self.contents = contents
        self.now = now
    }

    public func status() throws -> HookInstallStatus {
        guard let current = try load() else { return .notInstalled }
        return current == contents ? .installed : .partial
    }

    public func preview(_ action: HookInstaller.Action) throws -> HookInstaller.Preview {
        let current = try load() ?? ""
        return HookInstaller.Preview(before: current, after: action == .install ? contents : "")
    }

    @discardableResult
    public func install() throws -> HookInstaller.Result {
        let current = try load()
        if current == contents { return HookInstaller.Result(changed: false, backupURL: nil) }
        let target = fileURL.resolvingSymlinksInPath()
        let backup = try current.map { try HookInstaller.writeBackup(of: Data($0.utf8), beside: fileURL, at: now()) }
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: target, options: .atomic)
        } catch {
            throw HookInstallerError.io(error.localizedDescription)
        }
        return HookInstaller.Result(changed: true, backupURL: backup)
    }

    @discardableResult
    public func uninstall() throws -> HookInstaller.Result {
        guard let current = try load() else { return HookInstaller.Result(changed: false, backupURL: nil) }
        // An edited copy may hold someone's changes: keep them beside the file.
        let backup = current == contents
            ? nil : try HookInstaller.writeBackup(of: Data(current.utf8), beside: fileURL, at: now())
        do {
            // Removes the directory entry itself: a link into a dotfiles checkout goes, its target stays.
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw HookInstallerError.io(error.localizedDescription)
        }
        return HookInstaller.Result(changed: true, backupURL: backup)
    }

    /// At launch: replaces an installed, outdated copy of WhoIsWorking's own plugin (OPC-09), backing up
    /// the old one. Leaves a missing file missing and never writes through a symbolic link.
    /// Returns whether it wrote.
    @discardableResult
    public func updateIfOutdated() throws -> Bool {
        let type = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.type] as? FileAttributeType
        guard type != .typeSymbolicLink, try status() == .partial else { return false }
        return try install().changed
    }

    /// The file's text, nil when missing. Throws for a file WhoIsWorking did not write.
    private func load() throws -> String? {
        let target = fileURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }
        let text: String
        do { text = try String(contentsOf: target, encoding: .utf8) } catch {
            throw HookInstallerError.io(error.localizedDescription)
        }
        guard text.hasPrefix(OpenCodePlugin.marker) else {
            throw HookInstallerError.unexpectedShape("\(fileURL.lastPathComponent) is not WhoIsWorking's plugin")
        }
        return text
    }
}

// MARK: - Adapter

/// Maps what the plugin sends (an OpenCode v2 event with `data` trimmed and a `whoisworking` note
/// holding `parentID`, `rootID`, `directory` and `title`) to common events.
public enum OpenCodeAdapter {
    public static func event(from data: Data, receivedAt date: Date) -> AgentEvent? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String,
            let body = json["data"] as? [String: Any]
        else { return nil }
        let note = json["whoisworking"] as? [String: Any] ?? [:]
        let form = body["form"] as? [String: Any]
        guard let sessionId = nonEmpty(body["sessionID"]) ?? nonEmpty(form?["sessionID"]) else { return nil }

        // A subagent's child session acts on the session the user sees (OPC-05).
        let parent = nonEmpty(note["parentID"]) ?? (type == "session.created" ? nonEmpty(body["parentID"]) : nil)
        let root = parent.map { nonEmpty(note["rootID"]) ?? $0 }
        guard let kind = root == nil ? rootKind(type, body) : childKind(type, body) else { return nil }

        // The event's own time, so the reducer drops a late message instead of applying it.
        let eventDate = (json["created"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) } ?? date
        let location = (json["location"] as? [String: Any])?["directory"]
        let folder = root == nil
            ? nonEmpty(location) ?? nonEmpty(note["directory"]) ?? nonEmpty((body["location"] as? [String: Any])?["directory"])
            : nil
        var event = AgentEvent(sessionId: root ?? sessionId, date: eventDate, agent: .openCode, cwd: folder, kind: kind)
        if root == nil {
            let ownTitle = type == "session.created" || type == "session.renamed" ? nonEmpty(body["title"]) : nil
            event.name = ownTitle ?? nonEmpty(note["title"])
        }
        return event
    }

    private static func rootKind(_ type: String, _ body: [String: Any]) -> AgentEvent.Kind? {
        switch type {
        case "session.created": return .sessionStarted
        case "session.renamed": return .renamed
        case "session.deleted": return .sessionEnded
        case "session.execution.started": return .promptSubmitted
        case "session.execution.succeeded": return .stopped(lastMessage: nil)
        case "session.execution.failed":
            let message = nonEmpty((body["error"] as? [String: Any])?["message"])
            return .failed(error: message ?? "OpenCode run failed")
        case "session.execution.interrupted":
            // A superseded execution is followed straight away by the next one.
            return body["reason"] as? String == "superseded" ? nil : .interrupted
        case "session.step.started": return .activity(nil)
        case "session.tool.called": return .toolStarted(tool(body), subagent: false)
        default: return sharedKind(type, body)
        }
    }

    private static func childKind(_ type: String, _ body: [String: Any]) -> AgentEvent.Kind? {
        switch type {
        case "session.created": return .subagent(started: true, type: nonEmpty(body["agent"]))
        case "session.tool.called": return .toolStarted(tool(body), subagent: true)
        // The child's model is running, so the root is working (e.g. after the child's question was answered).
        case "session.step.started": return .activity(nil)
        default: return sharedKind(type, body)
        }
    }

    /// Requests to the user count wherever they come from.
    private static func sharedKind(_ type: String, _ body: [String: Any]) -> AgentEvent.Kind? {
        switch type {
        case "permission.asked":
            guard let id = nonEmpty(body["id"]) else { return nil }
            return .permissionRequested(permission(body, id: id))
        case "permission.replied":
            return nonEmpty(body["requestID"]).map { .permissionReplied(requestId: $0) }
        case "form.created":
            return .waitingForReply(message: nonEmpty((body["form"] as? [String: Any])?["title"]))
        default: return nil
        }
    }

    private static func permission(_ body: [String: Any], id: String) -> ToolActivity {
        let action = nonEmpty(body["action"]) ?? "permission"
        let resources = (body["resources"] as? [String] ?? []).filter { !$0.isEmpty }
        let label = action.replacingOccurrences(of: "_", with: " ").capitalizedFirst
        let summary: String = switch resources.count {
        case 0: label
        case 1: "\(label): \(resources[0])"
        default: "\(label): \(resources[0]) and \(resources.count - 1) more"
        }
        return ToolActivity(
            name: action, summary: ClaudeCodeAdapter.shorten(summary),
            detail: resources.isEmpty ? nil : resources.joined(separator: "\n"), requestId: id)
    }

    /// OpenCode's tool names map onto Claude Code's for the activity line.
    static func tool(_ body: [String: Any]) -> ToolActivity {
        let name = nonEmpty(body["name"]) ?? "tool"
        var input = body["input"] as? [String: Any] ?? [:]
        if let path = input["filePath"] { input["file_path"] = path }
        let claudeName: String = switch name {
        case "shell", "bash": "Bash"
        case "read": "Read"
        case "write": "Write"
        case "edit", "patch", "multiedit": "Edit"
        case "grep": "Grep"
        case "glob", "list": "Glob"
        case "webfetch": "WebFetch"
        case "task", "subagent": "Task"
        default: name
        }
        var activity = ClaudeCodeAdapter.tool(["tool_name": claudeName, "tool_input": input])
        activity.name = name
        return activity
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        return s
    }
}
