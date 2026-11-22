# Notch agent monitor: research, implementation plan, design plan

Draft, 2026-11-22. Items marked **(my call)** are my proposals, not things you agreed to.

This is the research and design record. The requirements now live in [`specs/`](specs/README.md).

## 1. What it is

A small macOS app that lives in the MacBook notch. It is invisible while nothing needs you, opens on hover, and shows every AI agent session on the machine: which are working, which are waiting on you, which finished. Downloaded from a web page, not the App Store.

## 2. What I found

### Your machine

| Thing | Finding | Consequence |
|---|---|---|
| Hardware / OS | MacBook Pro M4, macOS 27.2, Xcode 27.2, Swift 6.4 | Has a notch; can build with the current SDK and Liquid Glass |
| Agents installed | Claude Code 2.1.329 (CLI + desktop), Codex CLI 0.163 + ChatGPT/Codex desktop, cursor-agent + Cursor, OpenCode | These four are the v1–v2 target list |
| Claude Code session files | `~/.claude/sessions/<pid>.json` already holds `pid`, `sessionId`, `cwd`, `name`, `status` (`busy`…), `entrypoint` (`claude-desktop`, cli) | Free discovery and liveness for Claude sessions, including desktop-app ones, with no hook installed |
| Existing hooks | `herdr` scripts in `~/.claude/hooks`, `~/.codex`, `~/.cursor`; an `orca` status plugin in OpenCode; 14 hook events already configured in Claude settings | The installer must merge into these files and back them up. It must never overwrite them |
| Code signing | 0 valid signing identities | Browser download needs an Apple Developer Program membership ($99/yr) for a Developer ID certificate |

### How agents report state

| Agent | Mechanism | "Needs you" signal | Session id + folder |
|---|---|---|---|
| Claude Code | Hooks in `~/.claude/settings.json` (or shipped as a plugin). Command and HTTP handlers | `PermissionRequest`, `Notification` (`permission_prompt`, `idle_prompt`, `elicitation_dialog`, `agent_needs_input`) | `session_id`, `cwd` on every event |
| Codex CLI | `~/.codex/hooks.json`, near-identical event names | `PermissionRequest` | `session_id`, `cwd` |
| Cursor | `~/.cursor/hooks.json` | No dedicated event. Infer from `beforeShellExecution` / `beforeMCPExecution` with no follow-up | `conversation_id`, `workspace_roots` |
| OpenCode | JS plugin in `~/.config/opencode/plugins/` | Permission `evaluate` hook (names unconfirmed) | `sessionID`; folder only partly |

The current plans for the next local integrations are in the [Cursor](specs/11-cursor-adapter.md), [OpenCode](specs/12-opencode-adapter.md), and [Antigravity](specs/14-antigravity-adapter.md) drafts. The table above records the initial research.

### Existing apps

At least six already do this: claude-notch, Nook, Notch (MinhTamCK), NotchAgent, CodeIsland, Chimlo. They share one architecture: hook script → local Unix socket → SwiftUI panel pinned to the notch. Common weaknesses:

- Almost none are signed and notarized. Users hit the "Open Anyway" wall or build from source.
- No auto-update.
- Most are always visible and bundle extras (music, Pomodoro, clipboard).
- Reported bugs: hooks go silent after sleep; dead hook paths left behind after uninstall.

So the gap is a quiet, hidden-by-default monitor that installs cleanly and updates itself. That matches what you described.

## 3. Approaches

| | A. Hooks only | B. Hooks + session files **(my pick)** | C. No hooks: poll processes and transcripts |
|---|---|---|---|
| How | Every agent posts events to the app | Hooks for live state; session files and process checks for discovery and cleanup | Watch `ps`, session files, transcript files |
| Accuracy of "needs you" | High | High | Low for Codex/Cursor/OpenCode |
| Sessions started before the app | Missed | Found | Found |
| Crashed sessions | Stuck forever | Cleaned up when the pid dies | Cleaned up |
| Setup | Edits config files | Edits config files | None |

B costs little more than A and fixes its two known failure modes.

## 4. Implementation plan

**Stack (my call):** Swift 6, SwiftUI inside an AppKit `NSPanel`, no third-party notch library. The window code is about 200 lines and owning it avoids a dependency for the core of the app. Minimum macOS 15, Liquid Glass controls on 26+. Not sandboxed, because it must read `~/.claude` and friends, which is fine outside the App Store.

**Parts**

1. `AgentCore` (Swift package, no UI). Session model, a pure state reducer (event in, state out), and one adapter per agent that maps raw hook JSON to common events.
   States: working · needs approval · waiting for your reply · done (unseen) · idle · error.
2. Ingest. A Unix socket at `~/Library/Application Support/<App>/events.sock` (owner-only). One tiny hook script forwards stdin to it and exits immediately, so a closed app never slows an agent down.
3. Discovery. Watch `~/.claude/sessions/`, check pids every few seconds, re-scan on wake from sleep.
4. Installer. Per-agent toggle in Settings. Merges hook entries, writes a timestamped backup, tags its entries so uninstall removes exactly those.
5. Notch window. Borderless non-activating panel above the menu bar, sized from `NSScreen.safeAreaInsets` and `auxiliaryTopLeftArea/RightArea`, present on all Spaces and over full-screen apps. Falls back to a top-centre pill on screens without a notch.
6. App shell. Menu-bar-less agent app (`LSUIElement`), Settings window, launch at login.

**Phases**

| Phase | Result | Check |
|---|---|---|
| 0. Spike (1 day) | Black panel that hugs the notch and expands on hover | Screenshot on built-in and external display |
| 1. Core | Reducer + Claude Code adapter | Unit tests written first, from recorded real hook payloads |
| 2. Claude end to end | Socket, hook script, installer, discovery; real sessions show live | Tests for installer merge/uninstall; manual run with 3 sessions |
| 3. UI | Collapsed, peek, expanded states; click a row to jump to its terminal/app | Screenshots, VoiceOver pass |
| 4. Codex, then Cursor, OpenCode | One adapter each | Adapter tests from recorded payloads |
| 5. Ship | Developer ID signing, hardened runtime, `notarytool`, stapled DMG, Sparkle 2 updates, download page | Install on a clean user account from the downloaded DMG |

**Later, not v1 (my call):** Allow/Deny from the notch, usage limits, remote machines.

## 5. Design plan

**Behaviour**

```
Idle (nothing running)        [ notch ]                     nothing drawn
Working                       [ notch ]                     nothing drawn (your "hidden by default")
Needs you              ● 2 ─[ notch ]─ 4m                  small wings appear, amber, no sound by default
Hover / click         ┌──────[ notch ]──────┐
                      │ ● api-server   needs approval  2m │
                      │ ◐ website      editing files   8m │
                      │ ✓ translate    done            1m │
                      └────────────────────────────────────┘
```

- Open: hover with a short dwell (about 150 ms) so passing the cursor to the menu bar does not trigger it. Close: cursor leaves, or Esc.
- "Drag" I read as dragging down from the notch to pin it open. Tell me if you meant something else.
- Whether "working" should show anything at all is the main open design choice. I'd show nothing and only surface on "needs you" and "done".

**Visual rules**

- The panel body is pure black with the notch's corner curve, so it reads as the notch growing. Glass belongs only on controls inside the expanded panel, not on the body.
- One colour per state, always paired with a shape or icon so it works without colour: amber needs you, green done, neutral working, red error.
- SF Pro and SF Symbols. Agent badges use the product's colors.
- Spring animation for expand; respect Reduce Motion.

**References from Mobbin** (iOS Dynamic Island, the closest pattern)

- [Cursor](https://mobbin.com/screens/9744189c-82c8-4c22-ba25-a521fe85105b?utm_source=claude-code&utm_medium=ai-assistant&utm_source_platform=mcp): agent count on the left, elapsed time on the right. This is the model for the wings.
- [WHOOP](https://mobbin.com/screens/b65ab661-c2c3-4989-a404-629011ba0d77?utm_source=claude-code&utm_medium=ai-assistant&utm_source_platform=mcp), [Jomo](https://mobbin.com/screens/37fe77cb-8f7e-4762-961d-89e3097459a2?utm_source=claude-code&utm_medium=ai-assistant&utm_source_platform=mcp): one glyph plus one number, nothing else.
- [Perplexity](https://mobbin.com/screens/4ea08f69-9f99-40a6-bc83-f003dcd20d3c?utm_source=claude-code&utm_medium=ai-assistant&utm_source_platform=mcp), [ChatGPT](https://mobbin.com/screens/fee76439-e4ce-4ff1-88fb-5f50a6bdf114?utm_source=claude-code&utm_medium=ai-assistant&utm_source_platform=mcp): one-line "what the agent is doing now" rows, for the expanded list.

**Process**

1. Mobbin: one more pass for session lists, empty states, settings.
2. Claude Design: mock the three states (hidden, wings, expanded) plus Settings, in two or three visual directions, on a real MacBook menu-bar backdrop. You pick one.
3. Apple HIG and Liquid Glass skills: review the chosen direction, then guide the SwiftUI build.
4. Phase 0 spike runs alongside step 2, because hover feel can only be judged on the real notch.

## 5a. Settled design (2026-11-22)

Chosen by you from the Claude Design canvas and confirmed on the real notch with the spike in `perch-spike/`.

- **Hidden:** nothing drawn while sessions are idle or working.
- **Wings (from direction A):** amber dot + count of sessions needing you on the left, longest wait time on the right. 70 pt each side of the notch.
- **Expanded (direction B):** 560 pt wide panel with sections Needs you, Working, Done. The Needs you card shows the full command and an "Open session" button. Other sessions are 44 pt rows.
- **Hover:** opens after a 150 ms dwell on the notch or wings; closes 250 ms after the cursor leaves the panel. You confirmed this feels right.
- **Window:** borderless non-activating `NSPanel` at menu-bar level + 3, sized from `safeAreaInsets` and `auxiliaryTopLeftArea/RightArea` (your notch: 185 × 32 pt). Click-through while collapsed.
- **Phase 0 is done.** The spike is throwaway; the real app reuses its approach, not its code.
- **Still to mock:** Settings, the empty state (no sessions), and the no-notch pill.

## 6. Decisions

Decided 2026-11-22 (you asked me to choose):

1. **v1 is status only.** Approve/deny from the notch comes in v2, once the status is trustworthy.
2. **Just for you first, on GitHub Releases, unsigned.** No Developer Program yet. Phase 5 splits in two: 5a is an unsigned DMG on GitHub with Sparkle updates; 5b (signing and notarization, $99/yr) happens only when you want strangers to install it without the "Open Anyway" step.
3. **Working name: Perch.** Placeholder, easy to change before 5a. Renamed on 2026-11-22 to **WhoIsWorking** (shown as "Who's Working"): "Perch" is taken by several Mac apps, two of them agent monitors. The rest of this document keeps the old name as written at the time.

## Sources

- Claude Code hooks: https://code.claude.com/docs/en/hooks
- Codex hooks: https://developers.openai.com/codex/hooks
- Cursor hooks: https://cursor.com/docs/agent/hooks
- OpenCode plugins: https://opencode.ai/docs/plugins/
- Apple, Developer ID and notarization: https://developer.apple.com/developer-id , https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- Existing apps: https://github.com/eyyupcanisler/claude-notch , https://github.com/oa1mgo/nook-notch , https://github.com/MinhTamCK/notch , https://github.com/TeamNoSleepz/notch-agent , https://dev.to/krisying/i-turned-my-macbooks-notch-into-a-control-center-for-ai-coding-agents-2o57 , https://www.producthunt.com/products/chimlo-agents-in-your-macbook-notch
- DynamicNotchKit (considered, not chosen): https://github.com/MrKai77/DynamicNotchKit
