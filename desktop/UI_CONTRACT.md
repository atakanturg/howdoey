# Howdoey UI handoff — version 1

The interface is now defined in `Sources/Howdoey/UIContract.swift` (read that file for exact types). Codex implements its methods in `AppModel.swift` and owns app lifecycle, capture, permissions, reasoning, overlays' window lifecycle, and actions.

Claude owns **only** `Sources/Howdoey/UI/`. Do not modify the shared interface, package, app entry point, coordinator, backend, tests, or website. The app has a temporary backend test panel outside `UI/` so Codex can compile and test independently. Claude should provide:

```swift
import SwiftUI
import HowdoeyCore
struct HowdoeyPanelView: View {
    @ObservedObject var model: AppModel
    var body: some View { /* real UI, backed by model */ }
}
```

Use the same module (no separate package). Minimum deployment is macOS 14. Preferred panel size is 420 × 680 points; respect a 360 × 480 minimum. Keep chat, mode selector, selection preview, pending approval, settings, Stop, and error presentation inside the panel; Codex switches the hosting view during integration. Don't create an `@main`, NSApplicationDelegate, provider client, NSPanel, global event monitor, or replacement model.

## Binding rules

Editable: `mode`, `draft`, `configuration.endpoint`, `configuration.model`, `configuration.sendImages`, `apiKeyInput`, `providerPreset`, `showSettings`. Other published properties are read-only from UI. Disable mode changes while `isBusy`. Use `canSubmit` and `canCheckProgress`. `messages` is the entire session; no history is saved to disk. Render plain text or safe Markdown without auto-opening links.

Calls:
- Selection: `selectRegion()`, `selectElement()`, `selectWindow()`, `clearSelection()`.
- Session: `submit()`, `stop()`, `checkProgress()`, `clearConversation()`, `closePanel()`.
- Approval: `approve()`, `cancelApproval()`. Legacy presentation compatibility only; no computer execution is available.
- File controls are removed; do not call the old file selection/undo methods.
- Permissions: `refreshPermissions()`, `requestAccessibility()`, `requestScreenRecording()`, `openAccessibilitySettings()`, `openScreenRecordingSettings()`.
- Provider: call `applyProviderPreset()` after picker changes, `saveSettings()` before leaving settings, `fetchModels()` or `testProvider()` for real network checks. Display `settingsStatus`. API-key field must be `SecureField`. The screenshot toggle is opt-in and defaults off. The first request sends selected AX/OCR; later agent steps inspect the target app's current window.

## Overlays

Codex supplies working fallback selection and demonstration overlays outside UI. Claude may optionally provide pure SwiftUI overlay content after panel integration; coordinate the content interface first. Do not create duplicate capture, input monitoring, or window lifecycle. Coordinates in `DemonstrationTarget.rect` are global Quartz points, not local SwiftUI or AppKit coordinates.

## Integration

Claude reports when `HowdoeyPanelView(model:)` compiles. Codex then changes a single hosting-view selection in the coordinator and verifies the app. Do not change coordinator yourself. No fake running-app results; clearly isolated SwiftUI previews may use fixtures.

## Current integration

The actual Claude root is `ChatPanelView(model:)`, and Codex has connected it in `AppCoordinator.swift`. `INTEGRATION_STATUS.md` records lifecycle ownership and remaining UI follow-ups. UI should treat read-only-by-contract published state as display state even though its internal setters are visible within the shared executable module. Opening settings during an active task now stops it before allowing edits. Provider endpoint/key/model are frozen per submitted request; disabling image sharing takes effect immediately.

## Lifecycle ownership (current)

AppCoordinator + OverlayController own all running-app windows and presentation hooks. UIHost is not installed. Do not install it, replace the coordinator, package, or restart the app from Claude.

## Current scope — user update

Only Ask and Show Me are available. Do It and file-operation controls were removed at the user's explicit request while Claude was paused. Codex made the minimal corresponding UI edits in ChatPanel and SettingsView. Do not reintroduce execution, file picking, or approval flows. `approve()` remains a no-op compatibility entry point that stops the session.

`canSubmit` no longer requires an observation. Selection is optional: submitting without an explicit selection captures the last active external application's current window. Explicit selection remains until `clearSelection()`, which restores automatic window context. Use the live contract as authoritative; legacy file fields must not be presented as available functionality.

## Shared AI integration

ProviderPreset now includes `shared` (Howdoey shared AI). Its local-development endpoint is `http://127.0.0.1:8766/v1`. The existing secure credential field holds a tester access token in this mode; never ask end users for the developer Groq key. The relay forwards context to Groq even when its URL is localhost. A Codex-owned RelaySetupNotice supplies this clarification and the local developer setup link without modifying Claude's UI files. Permission status polls macOS every two seconds; false status must never be replaced with a fabricated green state. The main chat is an activating ChatWindow to ensure real keyboard focus; overlays remain non-activating.

## Simplified guidance — user update

The user requested a quiet target highlight instead of the animated pseudo-cursor and large selection presentation. The running backend uses TargetOutline and QuietSelectionSurface from Overlays.swift, with compact Check progress/Stop controls. No dim veil, separate caption or simulated pointer is displayed during Show Me. The UI-owned DemoOverlayController/SelectionOverlayController remain uninstalled. Do not restore the previous presentation through UIHost. Controls sent to the model include highlightable=true only for compact visible targets; page containers are excluded.

### Latest user-requested overrides
- Show Me is the sole product mode. Do not restore an Ask/Show Me toggle.
- Use “How can I help?” for the message prompt; omit instructional filler.
- While guiding, use the native side card and follow-up input rather than
  reopening the full conversation/history.
- Native side-card lifecycle, click observation and verification remain owned
  by Codex in AppCoordinator, AppModel and Overlays.
