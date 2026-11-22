import Foundation

/// `Perch hooks <status|preview|install|uninstall> [--settings <path>]`
///
/// Command-line access to the same installer the Settings window uses. `preview` prints the file
/// as it would be written and changes nothing. Default settings path: ~/.claude/settings.json.
public enum HooksCommand {
    public static func run(
        _ args: [String],
        defaultSettings: URL = PerchPaths.claudeSettings,
        hookScript: URL = PerchPaths.hookScript,
        output: (String) -> Void = { print($0, terminator: "") }
    ) -> Int32 {
        var rest = args
        var settings = defaultSettings
        if let i = rest.firstIndex(of: "--settings"), i + 1 < rest.count {
            settings = URL(fileURLWithPath: (rest[i + 1] as NSString).expandingTildeInPath)
            rest.removeSubrange(i ... i + 1)
        }
        let installer = ClaudeHookInstaller(settingsURL: settings, hookCommand: PerchPaths.hookCommand(agent: "claude-code"))
        do {
            switch rest.first {
            case "status":
                output("\(settings.path): \(try installer.status())\n")
            case "preview":
                let action: ClaudeHookInstaller.Action = rest.dropFirst().first == "uninstall" ? .uninstall : .install
                output(try installer.preview(action).after)
            case "install":
                try HookScript.write(to: hookScript)
                let result = try installer.install()
                output(result.changed ? "Installed. Backup: \(result.backupURL?.path ?? "none (new file)")\n" : "Already installed; nothing changed.\n")
            case "uninstall":
                let result = try installer.uninstall()
                // The script serves the default settings file; only uninstalling from that file may remove it.
                if settings.resolvingSymlinksInPath().path == defaultSettings.resolvingSymlinksInPath().path {
                    try? FileManager.default.removeItem(at: hookScript)
                }
                output(result.changed ? "Removed. Backup: \(result.backupURL?.path ?? "none")\n" : "Not installed; nothing changed.\n")
            default:
                output("usage: Perch hooks <status|preview [install|uninstall]|install|uninstall> [--settings <path>]\n")
                return 2
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            return 1
        }
    }
}
