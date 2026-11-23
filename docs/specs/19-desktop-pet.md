# 19 Desktop pet

Status: draft
Related spec: [08 Notch UI](08-notch-ui.md)

## Purpose

Let users choose a pet that lives on the screen and opens the WhoIsWorking session panel. The proposed first version offers one pet as an alternative to the notch or no-notch pill.

## Requirements

### PET-01 Choose how to open WhoIsWorking

Given the display option in Settings, when a user chooses the desktop pet, it becomes the entry point for the session panel. The user can switch back to the notch or pill through Settings. Restore the choice on relaunch and keep the same live sessions when switching modes.

### PET-02 Open the session panel from the pet

Given a visible pet, when the user activates it by click or an accessible action, show the same session content and controls available from the notch. The pet can signal that a session needs attention, with a cue that can be understood without color and through VoiceOver. Access to Settings and the session actions remains available in pet mode.

### PET-03 Keep the pet out of the way

Given a pet on the screen, its input region follows its visible interaction area so surrounding space remains available to other apps. If the display arrangement changes, place the pet somewhere reachable. With Reduce Motion enabled, use a static pet with an accessible attention cue.

## Planned verification

Try both display modes with a live session waiting for approval. Check that both entry points show the same session and actions, and that switching modes or relaunching restores the selected entry point. Check input around the pet, VoiceOver, Reduce Motion, and recovery after disconnecting its display.

## Open questions

- Should the pet stay in one spot, allow dragging, or roam on its own?
- Should it float above other windows or live on the desktop? What should happen across Spaces and in full-screen apps?
- Should pet mode replace the notch or can users enable both? Should the pet be visible when no session needs attention?
- Which character and attention cues should the first design use?
