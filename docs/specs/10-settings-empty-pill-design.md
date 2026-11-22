# 10 Design for Settings, empty state and no-notch pill

Status: draft
Depends on: `08-notch-ui.md`
Workflow: the `perch-design` skill

## Purpose

`docs/plan.md` §5a settled the wings and the expanded panel on a Claude Design canvas. Three screens were built without a mock: Settings, the empty state, and the no-notch pill. This spec covers designing them properly and bringing the code in line.

## Requirements

### DSN-01 References first

Each of the three screens has at least three references from Mobbin (macOS or iOS apps with the same kind of screen), linked in this file with one line on what is taken from each.

### DSN-02 Directions on a canvas

Each screen is mocked in two or three directions on a Claude Design canvas, on a real MacBook menu-bar backdrop, next to the settled wings and expanded panel so they read as one app. The user picks one direction per screen. The canvas link and the choice are recorded in `docs/plan.md` §5a.

### DSN-03 Settings

Settings is a standard macOS settings window: one section per agent with hook status, install and uninstall, a preview of the change before it is written, the backup location after a change, and Quit. It follows the Apple HIG for settings windows and uses system controls, so it gets Liquid Glass from the system on macOS 26 and later with no custom glass code.

### DSN-04 Empty state

The empty state says in one line what Perch shows and has one action. With hooks installed there is no action.

### DSN-05 No-notch pill

On a screen without a notch the pill shows the same two facts as the wings (count, longest wait), at the top centre, and expands to the same panel.

### DSN-06 Panel rules still hold

UI-04 and UI-05 apply: black body, glass only on controls inside the expanded panel, every colour paired with a shape. Custom glass APIs sit behind `#available(macOS 26, *)` because the package supports macOS 15.

### DSN-07 Accessibility

Every new control has a VoiceOver label, text meets contrast on the black body, and motion respects Reduce Motion.

### DSN-08 Spec and snapshots updated

When a direction is built, `08-notch-ui.md` is updated to the new behaviour and the snapshots are re-rendered and checked by the `design-reviewer` subagent.

## Open questions

1. Should Settings get launch at login and a "show while working" option, or stay hooks-only for v1?
2. Should the pill sit under the menu bar or inside it?
