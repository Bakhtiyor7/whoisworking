---
name: whoisworking-design
description: Design or redesign a WhoIsWorking screen (notch wings, expanded panel, Settings, empty state, no-notch pill) using Mobbin references, a Claude Design canvas, and Apple HIG and Liquid Glass review, then build and verify it. Use for any visual or interaction change to WhoIsWorking, and for docs/specs/10-settings-empty-pill-design.md.
---

# WhoIsWorking design loop

The settled design is in `docs/plan.md` §5a and `docs/specs/08-notch-ui.md`. New work extends it; it does not restart it.

## Fixed rules

- The panel body is pure black with the notch's corner curve. Glass never goes on the body. It is allowed only on controls inside the expanded panel.
- One colour per state, always with an icon or shape: amber needs you, green done, red error, neutral working.
- SF Pro and SF Symbols. Agents are a small monochrome mark (CC, CX).
- Hidden by default: nothing is drawn while sessions are idle or working. The one exception is the setup hint (UI-16): white, never amber, until an agent is connected or the user dismisses it.
- The package supports macOS 15. Liquid Glass APIs (`glassEffect`, `GlassEffectContainer`, glass button styles) need `if #available(macOS 26, *)` with a plain fallback. Standard system controls in the Settings window get glass from the system and need no custom code.
- Respect Reduce Motion, give every control a VoiceOver label, and keep text contrast on black.

## Steps

1. **Scope.** Name the screen and the requirement ids it touches. If there is no requirement yet, add one with the `whoisworking-spec` skill.
2. **References (Mobbin).** Load the Mobbin search skill, then search for the pattern: Dynamic Island and live activities for the wings and pill, session or task lists for the panel, macOS settings windows for Settings, empty states. Keep three to five and write one line each on what to take. Add the links to the spec.
3. **Directions (Claude Design).** Mock two or three directions on a Claude Design canvas (the Artifact tool's design type), on a MacBook menu-bar backdrop, beside the settled wings and panel. Give the user the link and let them pick. Record the link and the choice in `docs/plan.md` §5a.
4. **Review (Apple HIG and Liquid Glass).** Check the chosen direction with the `apple-hig-designer` skill and the `liquid-glass` skill: control sizes, spacing, type sizes, where glass is right and where it is not, accessibility. Fix the mock before building.
5. **Build.** SwiftUI in `Sources/WhoIsWorking`. Text, ordering and anything with a rule goes in `AgentCore` (`Summary.swift`) behind a test first; views only lay it out.
6. **Verify.** Use the `whoisworking-verify-ui` skill to render snapshots. Ask the `design-reviewer` subagent, where available, to compare them with the spec. List what only a person at the notch can check.
7. **Record.** Update `08-notch-ui.md` to the new behaviour and run `scripts/check-specs.sh`.

## If a tool is missing

Mobbin, Liquid Glass and Apple HIG are plugins or personal skills, not part of this repo. If one is not available in your session, say which, continue with the others, and do not invent references or links.
