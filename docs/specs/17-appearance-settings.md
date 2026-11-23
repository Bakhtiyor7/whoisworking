# 17 Appearance settings

Status: draft
Related specs: [08 Notch UI](08-notch-ui.md), [10 Settings design](10-settings-empty-pill-design.md)

## Purpose

Give users a place in Settings to choose a theme and personalize the session panel. The proposed starting point is a theme picker with the current appearance as the default. [Winter](18-winter-theme.md) would be the first additional preset.

## Requirements

### APP-01 Choose a theme

Given Appearance in Settings, when a user chooses a theme, the supported surfaces show the new appearance immediately and the choice is restored on relaunch. The user can switch back to the default theme from the same control.

### APP-02 Set a custom background

Given an appearance that supports a custom background, when a user selects a valid local image, the app saves a local copy and uses it in the expanded panel. The image can be replaced or removed from Settings. If the app cannot import a new image, it keeps the current background and explains the problem. If the saved image becomes unreadable, the panel uses the selected theme's background.

The expanded panel is the proposed surface for images. Before this ships, update UI-04 to describe how custom imagery fits inside the black notch silhouette and behind readable session content.

### APP-03 Change the panel font

Given a supported font choice in Appearance, when a user selects it, session text updates and the choice is restored on relaunch. The panel uses the system font if the saved font is unavailable. The app keeps session names, requests, and controls legible with long content and preserves the existing state colors, shapes, and VoiceOver labels.

## Optional follow-ups

- Per-agent icon overrides for session rows and Needs you cards. A user could change or reset each agent's icon independently. Missing or invalid assets would fall back to the bundled icon, with the agent's full name still available to VoiceOver. Decide whether this starts with built-in alternatives or accepts local images.

## Planned verification

Check theme switching, restoring defaults, and relaunch. Check image import, replacement, removal, and fallback with an unreadable file. Capture the expanded panel with a busy image, a long session name, and a custom font to check contrast and fitting. Check VoiceOver with the customized appearance.

## Open questions

- Should background and font overrides follow the user across themes or be saved per theme?
- Should font choices come from a curated list or from the fonts installed on the Mac? Which panel text should they apply to?
- Which image formats and framing controls should the first import support?
