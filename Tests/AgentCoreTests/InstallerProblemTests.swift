import Foundation
import Testing
@testable import AgentCore

/// ONB-06: every installer refusal or failure the user sees names the file, what was left alone and
/// what to do. The raw detail is kept apart, for a second, dimmer line.
@Suite("Installer problems")
struct InstallerProblemTests {
    @Test func invalidJSONNamesTheFileAndTheFix() {
        let p = InstallerProblem(HookInstallerError.invalidJSON("Unexpected character '}' at 42"), action: .add, agent: .claudeCode)
        // Only the agent's file is promised unchanged: the hook script may already have been written.
        #expect(p.text == "Couldn't add the hook: ~/.claude/settings.json isn't valid JSON. Who's Working left it unchanged. Fix the file, then try again.")
        #expect(p.detail == "Unexpected character '}' at 42")
    }

    @Test func anUnexpectedShapeNamesTheFileAndTheFix() {
        let p = InstallerProblem(HookInstallerError.unexpectedShape("hooks.Stop is not an array"), action: .remove, agent: .codex)
        // The file may be valid for Codex; it is Who's Working that will not edit it.
        #expect(p.text == "Couldn't remove the hook: ~/.codex/hooks.json has entries Who's Working doesn't recognise. Who's Working left it unchanged. Check the file, then try again.")
        #expect(p.detail == "hooks.Stop is not an array")
    }

    @Test func aForeignPluginFileNamesTheFileAndTheFix() {
        // The plugin installer's only shape refusal: a file at its path that Who's Working did not write.
        let p = InstallerProblem(HookInstallerError.unexpectedShape("whoisworking.js is not WhoIsWorking's plugin"), action: .add, agent: .openCode)
        #expect(p.text == "Couldn't add the plugin: ~/.config/opencode/plugins/whoisworking.js is another file, not Who's Working's plugin. Who's Working left it unchanged. Move that file away, then try again.")
        #expect(InstallerProblem(HookInstallerError.unexpectedShape("x"), action: .read, agent: .openCode).text
            == "~/.config/opencode/plugins/whoisworking.js is another file, not Who's Working's plugin, so Who's Working leaves it alone. Move that file away to add the plugin.")
    }

    @Test func antigravityCommentsAreNamedAsTheLikelyCause() {
        // Antigravity allows comments in its hooks file; Who's Working cannot edit such a file safely.
        let p = InstallerProblem(HookInstallerError.invalidJSON("x"), action: .add, agent: .antigravity)
        #expect(p.text == "Couldn't add the hook: ~/.gemini/config/hooks.json has comments or isn't valid JSON, so Who's Working can't edit it safely. Who's Working left it unchanged. Remove the comments or fix the file, then try again.")
    }

    @Test func aFailedReadOrWriteNamesTheFileWithoutClaimingNothingChanged() {
        let p = InstallerProblem(HookInstallerError.io("Permission denied"), action: .add, agent: .cursor)
        #expect(p.text == "Couldn't add the hook: Who's Working couldn't read or write ~/.cursor/hooks.json. Check that you can edit the file and its folder, then try again.")
        #expect(p.detail == "Permission denied")
    }

    @Test func aFileThatCannotBeReadIsLeftAlone() {
        #expect(InstallerProblem(HookInstallerError.invalidJSON("x"), action: .read, agent: .claudeCode).text
            == "~/.claude/settings.json isn't valid JSON, so Who's Working leaves it alone. Fix the file to add or remove the hook.")
        #expect(InstallerProblem(HookInstallerError.io("x"), action: .read, agent: .codex).text
            == "Who's Working couldn't read ~/.codex/hooks.json. Check that you can open the file.")
        #expect(InstallerProblem(HookInstallerError.unexpectedShape("x"), action: .read, agent: .antigravity).text
            == "~/.gemini/config/hooks.json has entries Who's Working doesn't recognise, so Who's Working leaves it alone. Check the file to add or remove the hook.")
    }

    @Test func aPluginUpdateFailureNamesThePluginFile() {
        let p = InstallerProblem(HookInstallerError.io("disk full"), action: .update, agent: .openCode)
        #expect(p.text == "Couldn't update the plugin: Who's Working couldn't read or write ~/.config/opencode/plugins/whoisworking.js. Check that you can edit the file and its folder, then try again.")
    }

    @Test func aHookScriptFailureNamesTheScriptAndLeavesTheAgentFileAlone() {
        // Adding a hook writes the shared hook script first; any error that is not the installer's comes from there.
        struct Other: Error, CustomStringConvertible { var description: String { "no space" } }
        let p = InstallerProblem(Other(), action: .add, agent: .claudeCode)
        #expect(p.text == "Couldn't add the hook: Who's Working couldn't write its hook script. ~/.claude/settings.json was left unchanged. Try again, and open an issue if it keeps failing.")
        #expect(p.detail == "no space")
        // Anything else promises nothing about the file.
        #expect(InstallerProblem(Other(), action: .remove, agent: .openCode).text
            == "Couldn't remove the plugin. Try again, and open an issue if it keeps failing.")
    }

    @Test func noTextStartsWithErrorOrHasADash() {
        let errors: [Error] = [HookInstallerError.invalidJSON("d"), HookInstallerError.unexpectedShape("d"), HookInstallerError.io("d")]
        for agent in AgentKind.allCases {
            for action in [InstallerProblem.Action.add, .remove, .read, .update] {
                for error in errors {
                    let text = InstallerProblem(error, action: action, agent: agent).text
                    #expect(!text.hasPrefix("Error"))
                    #expect(!text.contains("—") && !text.contains("–"))
                    #expect(!text.contains("(d)") && !text.contains(": d"), "the raw detail stays out of the text")
                }
            }
        }
    }
}
