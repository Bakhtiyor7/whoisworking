import Foundation

/// `WhoIsWorking hooks <status|preview [install|uninstall]|install|uninstall> [--agent <agent>] [--settings <path>]`
///
/// Command-line access to the same installers the Settings window uses. `preview` prints the file
/// as it would be written and changes nothing. Default files: ~/.claude/settings.json, ~/.codex/hooks.json,
/// ~/.cursor/hooks.json, ~/.gemini/config/hooks.json, and the plugin ~/.config/opencode/plugins/whoisworking.js.
public enum HooksCommand {
    static let usage =
        "usage: WhoIsWorking hooks <status|preview [install|uninstall]|install|uninstall> "
        + "[--agent claude-code|codex|cursor|antigravity|opencode] [--settings <path>]\n"

    public static func run(
        _ args: [String],
        defaultSettings: (HookTarget) -> URL = { $0.defaultSettingsURL },
        hookScript: URL = AppPaths.hookScript,
        defaultPlugin: URL = OpenCodePlugin.defaultURL,
        output: (String) -> Void = { print($0, terminator: "") }
    ) -> Int32 {
        var rest = args
        var target = HookTarget.claudeCode
        if let i = rest.firstIndex(of: "--agent"), i + 1 < rest.count {
            if rest[i + 1] == "opencode" {
                rest.removeSubrange(i ... i + 1)
                return runPlugin(rest, defaultPlugin: defaultPlugin, output: output)
            }
            guard let named = HookTarget.named(rest[i + 1]) else {
                output("unknown agent \(rest[i + 1]); use claude-code, codex, cursor, antigravity or opencode\n")
                return 2
            }
            target = named
            rest.removeSubrange(i ... i + 1)
        }
        var settings = defaultSettings(target)
        if let i = rest.firstIndex(of: "--settings"), i + 1 < rest.count {
            settings = URL(fileURLWithPath: (rest[i + 1] as NSString).expandingTildeInPath)
            rest.removeSubrange(i ... i + 1)
        }
        func installer(_ t: HookTarget, _ url: URL) -> HookInstaller {
            HookInstaller(target: t, settingsURL: url, hookCommand: AppPaths.hookCommand(agent: t.id))
        }
        let chosen = installer(target, settings)
        do {
            switch rest.first {
            case "status":
                output("\(settings.path): \(try chosen.status())\n")
            case "preview":
                let action: HookInstaller.Action = rest.dropFirst().first == "uninstall" ? .uninstall : .install
                output(try chosen.preview(action).after)
            case "install":
                try HookScript.write(to: hookScript)
                let result = try chosen.install()
                output(result.changed ? "Installed. Backup: \(result.backupURL?.path ?? "none (new file)")\n" : "Already installed; nothing changed.\n")
            case "uninstall":
                let result = try chosen.uninstall()
                // The script serves every agent's default file: remove it only when none of them still uses it,
                // and never because of a file elsewhere (`--settings`).
                if settings.standardizedFileURL == defaultSettings(target).standardizedFileURL {
                    HookScript.removeIfUnused(at: hookScript, defaultSettings: defaultSettings)
                }
                output(result.changed ? "Removed. Backup: \(result.backupURL?.path ?? "none")\n" : "Not installed; nothing changed.\n")
            default:
                output(usage)
                return 2
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            return 1
        }
    }

    /// OpenCode has a plugin file instead of hook entries (OPC-08). It does not use the hook script.
    static func runPlugin(_ args: [String], defaultPlugin: URL, output: (String) -> Void) -> Int32 {
        var rest = args
        var file = defaultPlugin
        if let i = rest.firstIndex(of: "--settings"), i + 1 < rest.count {
            file = URL(fileURLWithPath: (rest[i + 1] as NSString).expandingTildeInPath)
            rest.removeSubrange(i ... i + 1)
        }
        let installer = PluginInstaller(fileURL: file)
        do {
            switch rest.first {
            case "status":
                output("\(file.path): \(try installer.status())\n")
            case "preview":
                let action: HookInstaller.Action = rest.dropFirst().first == "uninstall" ? .uninstall : .install
                output(try installer.preview(action).after)
            case "install":
                let result = try installer.install()
                output(result.changed ? "Installed. Backup: \(result.backupURL?.path ?? "none")\n" : "Already installed; nothing changed.\n")
            case "uninstall":
                let result = try installer.uninstall()
                output(result.changed ? "Removed. Backup: \(result.backupURL?.path ?? "none")\n" : "Not installed; nothing changed.\n")
            default:
                output(usage)
                return 2
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            return 1
        }
    }
}
