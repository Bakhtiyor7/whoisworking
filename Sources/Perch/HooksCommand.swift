import AgentCore
import Foundation

/// `Perch hooks <status|preview|install|uninstall> [--settings <path>]`
///
/// Command-line access to the same installer the Settings window uses. `preview` prints the file
/// as it would be written and changes nothing. Default settings path: ~/.claude/settings.json.
enum HooksCommand {
    static func run(_ args: [String]) -> Int32 {
        var rest = args
        var settings = PerchPaths.claudeSettings
        if let i = rest.firstIndex(of: "--settings"), i + 1 < rest.count {
            settings = URL(fileURLWithPath: (rest[i + 1] as NSString).expandingTildeInPath)
            rest.removeSubrange(i ... i + 1)
        }
        let installer = ClaudeHookInstaller(settingsURL: settings, hookCommand: PerchPaths.hookCommand(agent: "claude-code"))
        do {
            switch rest.first {
            case "status":
                print("\(settings.path): \(try installer.status())")
            case "preview":
                let action: ClaudeHookInstaller.Action = rest.dropFirst().first == "uninstall" ? .uninstall : .install
                print(try installer.preview(action).after, terminator: "")
            case "install":
                try HookScript.write(to: PerchPaths.hookScript)
                let result = try installer.install()
                print(result.changed ? "Installed. Backup: \(result.backupURL?.path ?? "none (new file)")" : "Already installed; nothing changed.")
            case "uninstall":
                let result = try installer.uninstall()
                try? FileManager.default.removeItem(at: PerchPaths.hookScript)
                print(result.changed ? "Removed. Backup: \(result.backupURL?.path ?? "none")" : "Not installed; nothing changed.")
            default:
                print("usage: Perch hooks <status|preview [install|uninstall]|install|uninstall> [--settings <path>]")
                return 2
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            return 1
        }
    }
}
