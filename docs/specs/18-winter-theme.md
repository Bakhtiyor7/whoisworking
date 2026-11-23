# 18 Winter theme

Status: draft
Depends on: [17 Appearance settings](17-appearance-settings.md) for theme selection
Related spec: [08 Notch UI](08-notch-ui.md)

## Purpose

Offer an opt-in Winter theme with falling snow, snow resting on the notch edges or lower rim, and small pieces that fall away as the notch opens or closes. The proposed first version uses snow as the main decoration.

## Requirements

### WTR-01 Falling and settled snow

Given the Winter theme and a visible notch surface, show snowfall and a layer of settled snow along the chosen edge or bottom rim. Decorations leave status indicators, session text, and controls readable. The existing hover and click targets continue to work. Pause snowfall when its surface is hidden.

### WTR-02 Snow falls as the notch moves

Given settled snow on the notch, when the notch expands or collapses, small pieces fall away and disappear below the rim. If the user reverses the transition, the snow follows the current panel shape without leaving stray pieces behind.

### WTR-03 Reduce Motion

Given macOS Reduce Motion is enabled, show static snow trim in place of falling snow and falling pieces. Apply the change while the app is running if the system setting changes.

## Optional follow-ups

- Christmas or New Year accents such as lights or small trees.
- A bundled winter image for the expanded panel, using the background treatment from [Appearance settings](17-appearance-settings.md).

## Planned verification

Capture the collapsed and expanded notch with Winter selected. On a notched Mac, check snowfall, repeated expand and collapse, and switching themes while snow is visible. Repeat with Reduce Motion enabled and check that the session indicators and controls remain readable. Check the no-notch pill once its treatment is decided.

## Open questions

- Should the theme stay winter-only or offer festive accents in the first release?
- Should a collapsed notch with no attention needed show snow? Today that state draws nothing, so persistent snow would change UI-01.
- Should the no-notch pill get the same snow treatment or use a simpler decoration?
