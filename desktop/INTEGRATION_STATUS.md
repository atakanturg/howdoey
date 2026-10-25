# Integration status (Codex)

Claude's `UI/ChatPanel.swift`, `SelectionOverlay.swift` and supporting SwiftUI views compile against the shared AppModel. Codex has integrated `ChatPanelView(model:)` as the hosted root in AppCoordinator (the UI implementation's actual root name). Do not rename the root during active integration without coordination.

The running app uses **AppCoordinator + OverlayController** for all lifecycle and windows. The optional Claude UIHost/ChatPanelController/SelectionOverlayController/DemoOverlayController helpers are not installed, so there is only one lifecycle owner. Pure SelectionOverlayView is hosted by the backend controller; native element selection remains supported through its own fallback. Codex made minimal ChatPanel/SettingsView edits for the user-requested removal of Do It, optional selection copy and accurate shared-relay privacy/credential labels while Claude was paused.

BackendTestPanel is retained as an unused diagnostic fallback. No mock model is used in the running application.

UI follow-ups for Claude (only in UI files):
- Settings should explain that later agent steps inspect the target application's current window, not just the initial selected rectangle. Backend README already documents this.
- Disable provider/settings edits while the task is busy, or stop before changing them.
- UI_CONTRACT's requested `HowdoeyPanelView` can be a typealias to `ChatPanelView` if desired; coordinate before renaming existing integration.
- Do not call UIHost.install() in addition to AppCoordinator's hooks.

## Coordination resolution

The user explicitly confirmed that Codex owns backend, integration and builds; Claude owns UI only. A concurrent AppCoordinator rewrite to UIHost was preserved in `IntegrationNotes/PreviousUIHostCoordinator.swift.txt`. Codex restored the single AppCoordinator/OverlayController lifecycle and pure ChatPanelView hosting with `NSHostingView.sizingOptions = []`. Do not install UIHost or run package/restart commands from Claude. The test app must stay unchanged during TCC authorization.

Root chat hosting must retain a concrete width/height matching the native panel. A conditional safeAreaInset around an unbounded root caused a sampled SwiftUI layout loop at ~100% CPU during capture. AppCoordinator now hosts a fixed-size VStack with the settings notice below the chat. Do not reintroduce the unbounded/inset combination.

The running guide card is now NativeGuideCard in Overlays.swift (AppKit) with a visible target label/instruction and native Check progress/Stop controls. Chat text selection and animated scrollTo were removed to stop a reproducible layout freeze. Do not reintroduce the previous selection-overlay/animated LazyVStack combination without a live long-response + guide test. Minimal ChatPanel edits were required by the user’s explicit UI regression fix request while Claude was paused.

## Current requested interaction — Show Me only

User requested removal of Ask and the mode toggle. The running UI now submits
Show Me requests only. The shared core retains Ask decoding for compatibility,
but it is not exposed in the app. User-requested minimal ChatPanel edits remove
the toggle and filler text; the prompt is “How can I help?”.

During a request the main history panel hides. The Codex-owned native guide card
sits at a screen edge away from the target and retains a live follow-up field,
Check progress and Stop through observing, reasoning, verification and completion.
Each mouse-up in the guided application queues a 650ms debounced progress check.
Clicks during an in-flight response invalidate that decision; fresh observation
precedes another decision. No click coordinates or keystrokes are retained.
The existing local AX change watcher and manual progress button remain.

The user explicitly requested that testing stop. No further interactive tests
are authorized by this request; the final copy changes are built for their test.

## Latest iteration: longer sessions, clear chat and selection context

- Removed the total step-count cutoff. Unverified user clicks prompt reassessment
  rather than ending the session after three checks. Individual provider requests
  retain timeouts and target lookup has bounded technical retries.
- Native side-card instructions are complete, scrollable text; the prior text
  remains until a replacement decision arrives. Verified completion uses the
  “Good work!” heading.
- Clear chat is available on both the main header and compact card. It cancels
  pending work, clears conversation/history/selection/context and opens a new chat
  while retaining provider configuration.
- Stronger blue selection tint, transparent cutout, white/accent borders and
  corner handles. Tiny drags/clicks now hit-test Accessibility elements, including
  filename text exposed as AXValue. Small crops include neighboring context at
  Retina capture scale; the selected detail remains the model's priority.
- Website fetched from origin/main d4d8600. The checkout now tracks that remote
  from codex/desktop-demo. The original untracked root README was preserved at
  desktop/.local-backups/root-README-before-pull.md. Desktop files were retained.
- Local website preview is served by website/dev-server.mjs on loopback port8080.
  Download offers the existing real development ZIP, with its non-notarized
  status disclosed. Website placeholders remain labeled. No deployment made.
- User owns interactive testing; only compilation/packaging performed this turn.
