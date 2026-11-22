# 15 Click to session

Status: draft
Code: `Sources/AgentCore/` for route selection, `Sources/WhoIsWorking/` for navigation and UI
Depends on: `04-codex.md`, `05-ingest-and-hook-script.md`, `08-notch-ui.md` (UI-10)

## Purpose

Click a row in the expanded panel or the action on a Needs you card to return to the session that produced it. This is especially useful when several agents are working in the same project and one needs approval. Today both actions bring the owning app forward when it can be found. A shared daemon can hide the owning app, and activating an app leaves tab and conversation selection to that app. [Current click handler](../../Sources/WhoIsWorking/main.swift#L24-L28) · [Current app activation](../../Sources/WhoIsWorking/AppFocuser.swift)

## Requirements

### NAV-01 Exact destination when known

Given a row with a verified destination for an existing session, clicking either entry point opens the exact conversation, tab, or pane. Both entry points use the same routing decision. Match by host and session identity. A project path, window title, or shared daemon PID alone is insufficient, including when only one matching row is visible.

### NAV-02 Honest fallback

Given a known host and an uncertain or stale session destination, offer **Open in [app]** and bring that app forward. Use **Open session** for an exact route. If a click fails and no fallback is available, keep the panel usable and show **Session location unavailable**. The outcome and control label should be available to VoiceOver. A stale destination or denied terminal permission follows the same fallback rule.

### NAV-03 Navigation leaves the agent in control

Given a running session or one waiting for input or approval, navigating to it leaves its turn and pending request intact. Adopt only host actions that focus or open the existing UI destination. The agent still owns resume, restart, input, and approval actions. An unsuccessful handoff does not mark the session viewed as a side effect of the click. The expanded panel still marks completed rows viewed when it displays them, as specified by the existing reducer and panel behavior.

### NAV-04 Codex Desktop

Given a local Codex chat with a verified desktop origin and thread ID, open it via `codex://threads/<thread-id>`. Build the URL from the supported scheme and a validated ID. CLI sessions, IDE sessions, placeholders, and sessions with unknown origin use their own verified route or the app-level fallback. Confirm which installed client versions support the route before enabling it.

OpenAI documents the deep link, and Codex v0.171.0 uses the root thread ID as the session ID. WhoIsWorking already captures `session_id`. Matching the ID copied by the desktop app and identifying the source of a live hook are still to be verified. [Desktop deep links](https://learn.chatgpt.com/docs/app/commands#deep-links) · [Codex v0.171.0 source](https://github.com/openai/codex/blob/rust-v0.171.0/codex-rs/core/src/session/session.rs#L952-L975) · [Hook adapter](../../Sources/AgentCore/CodexAdapter.swift)

macOS can report a URL dispatch failure. A successful dispatch only confirms that the handler accepted the URL. Verify which chat actually opens and how the host handles a stale link in the live acceptance check.

### NAV-05 Direct terminal sessions

Given a live session with a uniquely identified local terminal tab or pane, select it and bring its window forward. Match a live controlling terminal device or a verified host-provided pane ID. Recheck process identity and tab or pane availability before acting, since process IDs and terminal devices can be reused. Ask for macOS Automation permission only when a user invokes a route that needs it. Keep the app-level fallback available when exact terminal navigation cannot run.

iTerm2 documents session activation. Apple Terminal’s installed scripting dictionary exposes a tab’s `tty` and whether it is `selected`. These interfaces establish feasibility. End-to-end tab selection and permission behavior still need checks on the supported app bundle. [iTerm2 session API](https://iterm2.com/python-api/session.html) · [macOS Automation](https://support.apple.com/guide/mac-help/allow-apps-to-control-other-apps-mchl108e1718/mac)

## Implementation order

1. **Prove the desktop route.** In a scratch project, collect minimal, anonymized hook metadata from Codex Desktop, CLI, and the VS Code extension. Compare the desktop hook’s `session_id` with **Copy chat deep link**. Verify that available origin evidence distinguishes the desktop chat from CLI and IDE sessions, including when a shared daemon handles hooks. Check the link with two live desktop chats open in that project. If origin remains ambiguous, start with terminals while investigating the desktop route.
2. **Ship one exact route and its fallback.** Keep route selection testable in `AgentCore` and invoke the host APIs from `AppFocuser.swift`. Resolve against the current session at click time. Wire the existing row and card actions through `main.swift` and `NotchViews.swift` so visible labels, VoiceOver, and failed handoffs reflect the destination. Preserve the [hook script contract](05-ingest-and-hook-script.md) and the [installer contract](06-hook-installer.md).
3. **Add direct terminal routes one host at a time.** Start with iTerm2, then verify Apple Terminal against its installed scripting dictionary and the signed bundle. Keep VS Code extension conversations and Claude Desktop on app-level navigation until there is a supported exact route. Evaluate tmux separately when the server, pane, and user’s attached client can all be identified. [VS Code URI handlers](https://code.visualstudio.com/api/references/vscode-api#window.registerUriHandler) · [Claude Desktop](https://code.claude.com/docs/en/desktop) · [tmux manual](https://man.openbsd.org/tmux.1)

Claude Code’s review preferred terminals first because the terminal device identifies a live tab even when two sessions share a project. Start with the desktop feasibility check because the documented link avoids terminal Automation. Use the terminal route first if desktop origin cannot be established. The interaction precedent is cmux, where clicking a notification goes to the workspace that sent it. [cmux notifications](https://cmux.com/docs/notifications)

## Acceptance checks

| Case | Expected result |
|---|---|
| Two desktop chats in the same project, one waiting for approval | Each row opens its own chat. The request still waits for approval. |
| Desktop and CLI or IDE sessions in the same project | Only the verified desktop row uses the desktop link. The other row opens its verified host or shows the applicable fallback. |
| Two same-folder terminal sessions in different tabs, windows, or split panes | Each click selects the matching live tab or pane. Moving the tab to another window still works if the host can find it by identity. |
| Shared daemon, stale or reused PID or terminal device, or multiple possible hosts | Use a known host fallback or show that the session location is unavailable. |
| Closed destination, missing URL handler, or denied or revoked Automation | Use the available app-level fallback. With no fallback, keep the panel usable and report the failure. The click does not change agent state. |

When implementing, add failing Swift Testing cases for routing and failure handling before writing the code. Add `Tests:` references to the relevant requirements and use `Verified by:` for native handoff and VoiceOver checks. Update UI-10 and the README to describe the coverage that ships. Run `swift build`, `swift test`, and `scripts/check-specs.sh` before calling implementation complete.

## Open questions

- What reliable origin signal do the installed Codex Desktop, CLI, and IDE builds expose, and does it survive a shared daemon or handoff?
- Which terminal automation interface works on the supported signed build with the fewest setup steps? Verify iTerm2’s scripting and Python API options before choosing one.
- If tmux is added later, how should navigation choose among multiple attached clients that can display the same pane?
