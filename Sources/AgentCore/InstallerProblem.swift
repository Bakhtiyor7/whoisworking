import Foundation

/// What the setup card and Settings say when an installer refuses or fails (ONB-06): the file, what
/// was left alone and what to do, in one text; the raw detail apart, for a second, dimmer line.
public struct InstallerProblem: Equatable, Sendable {
    public enum Action: Sendable {
        case add, remove, read
        /// Replacing an outdated copy of Who's Working's own plugin at launch (OPC-09).
        case update
    }

    public var text: String
    public var detail: String?

    public init(_ error: Error, action: Action, agent: AgentKind) {
        let path = SetupPrompt.displayPath(for: agent)
        let noun = agent == .openCode ? "plugin" : "hook"
        let lead: String = switch action {
        case .add: "Couldn't add the \(noun)"
        case .remove: "Couldn't remove the \(noun)"
        case .update: "Couldn't update the \(noun)"
        case .read: ""
        }

        // The installer refuses these before it writes. Only the agent's file is said to be unchanged:
        // adding a hook writes the shared hook script first.
        let unchanged = "Who's Working left it unchanged."

        guard let installerError = error as? HookInstallerError else {
            if action == .read {
                text = "Who's Working couldn't read \(path)."
            } else if action == .add, agent != .openCode {
                // The only step of adding a hook that throws something else: writing the hook script.
                text = "\(lead): Who's Working couldn't write its hook script. \(path) was left unchanged. "
                    + "Try again, and open an issue if it keeps failing."
            } else {
                text = "\(lead). Try again, and open an issue if it keeps failing."
            }
            detail = "\(error)"
            return
        }

        switch installerError {
        case .invalidJSON(let raw):
            detail = raw
            // Antigravity allows comments in its file; they are the likely cause there.
            if agent == .antigravity {
                let problem = "has comments or isn't valid JSON, so Who's Working can't edit it safely"
                text = action == .read
                    ? "\(path) \(problem). Remove the comments or fix the file to add or remove the hook."
                    : "\(lead): \(path) \(problem). \(unchanged) Remove the comments or fix the file, then try again."
            } else {
                text = action == .read
                    ? "\(path) isn't valid JSON, so Who's Working leaves it alone. Fix the file to add or remove the hook."
                    : "\(lead): \(path) isn't valid JSON. \(unchanged) Fix the file, then try again."
            }
        case .unexpectedShape(let raw):
            detail = raw
            if agent == .openCode {
                // The plugin installer's only shape refusal: a file there that Who's Working did not write.
                text = action == .read
                    ? "\(path) is another file, not Who's Working's plugin, so Who's Working leaves it alone. Move that file away to add the plugin."
                    : "\(lead): \(path) is another file, not Who's Working's plugin. \(unchanged) Move that file away, then try again."
            } else {
                // The file may be valid for the agent; it is Who's Working that will not edit it.
                text = action == .read
                    ? "\(path) has entries Who's Working doesn't recognise, so Who's Working leaves it alone. Check the file to add or remove the \(noun)."
                    : "\(lead): \(path) has entries Who's Working doesn't recognise. \(unchanged) Check the file, then try again."
            }
        case .io(let raw):
            detail = raw
            // A failed write may come after the backup was made, so the file is not promised unchanged.
            text = action == .read
                ? "Who's Working couldn't read \(path). Check that you can open the file."
                : "\(lead): Who's Working couldn't read or write \(path). Check that you can edit the file and its folder, then try again."
        }
    }
}
