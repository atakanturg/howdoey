# Local validation status — 2026-10-25

- Swift Command Line Tools build: passed, including Claude UI source.
- Seven core checks: passed (action policy, endpoint/path constraints, model JSON validation, collision-safe file move, changed-source rejection, symlink escape rejection).
- App packaging: local ARM64 .app + ZIP generated; Info.plist and ad-hoc signature verification passed.
- Native UI smoke test: app launch, chat panel, settings, empty-model error and screenshot sharing off by default were observed with computer-use tools.
- A concurrent integration/build changed AppCoordinator and replaced the app during TCC permission testing. The user confirmed Codex owns backend/integration/builds and Claude owns UI only. The previous coordinator was preserved in IntegrationNotes for reference; Codex reinstated a single window lifecycle using Claude's pure views and bounded host sizing. UIHost is not installed.
- Screen Recording is enabled in macOS for a Howdoey entry, but the running app reported both permissions unavailable after signature changes. Grant/access verification against the fixed final binary is pending. Do not claim TCC-gated functionality is validated until the app reports permission and a real capture succeeds.
- No provider model/key has been configured in the app. No live AI answer, guided step or full agent-driven Finder move has been validated yet. Automated tests perform real disposable-file moves, not model-generated responses.

Keep the current .app unchanged while granting permissions and running the demo. Developer ID or Apple Development signing with a stable identity is needed to avoid repeated privacy grants across builds; no signing identities are installed on this Mac. Ad-hoc builds are local development artifacts, not public releases.

## Follow-up validation

- Chat keyboard focus fixed by replacing the non-activating chat panel with an activating borderless NSWindow. Ordinary `h` and `i` key events produced `hi` in the real app field; test text was cleared.
- The status item now uses `Brand.menuBarImage()` from Claude's existing brand geometry, matching the in-app speech-bubble logo.
- Local Groq relay implemented with developer-only local setup, persistent hashed tester tokens, expiry/revocation, server-fixed model, per-user/global quotas, bounded inputs/output and sanitized errors. Seven Node tests pass in addition to seven Swift core checks (14 total).
- The first setup form rejected opaque browser Origin headers. Referrer policy and Origin handling were corrected while retaining mandatory random CSRF validation and rejection of explicit foreign origins; regression checks pass. Actual live Groq setup remains pending user input.
- Stable local development signing installed with explicit user authorization, restricted to codesign in the user trust domain. Two different signed code hashes retained exactly the same certificate-based designated requirement; strict signature verification passed. No browser/system trust roots added.
- Only Howdoey's stale Accessibility and ScreenCapture grants were reset with tccutil for the switch to the persistent identity. No unrelated app permissions were changed.
- Screen Recording **On** was observed inside the stable-signed app after the fresh grant. Accessibility grant is still pending. Full live Ask/Show Me/Do It validation still needs that permission and a configured real AI service.

## Test handoff

- Both Screen Recording and Accessibility were observed On in the stable-signed app.
- After a genuine source change, package rebuild and application restart, both grants remained On. This validates permission persistence with the local development identity on this Mac.
- Visible Cancel and Escape were manually verified to return from selection to the normal panel. The initial Control–Option–Space cancellation test failed; the local event handler was corrected and a subsequent live test returned to the normal panel before the fallback Escape. A 90-second timeout is implemented but its full duration has not been manually timed.
- Selection is closed and UI automation is stopped for user testing. The local relay remains running at port 8766, but its /health response still reports ready=false: the developer key/model have not yet been configured successfully. Live AI end-to-end workflows remain unvalidated, not claimed complete.

## Current scope and setup correction

- User narrowed scope to Ask and Show Me. Do It is removed from Mode and both chat presentations; model-requested execution and file selection/undo entry points were removed from AppModel.
- No explicit selection is required to submit. Each submission without a selection freshly observes the last active external application's current window. Explicit selection remains until cleared.
- Stored developer key was rejected by live Groq requests with HTTP 401; no successful live AI answer has been verified. Do not describe this as a model-ID-only issue.
- Relay setup now validates the key before enabling token creation, automatically selects an available chat model, offers a model dropdown and renders recoverable HTML errors. Eight Node tests and seven Swift checks passed; full app compilation passed before final copy changes.

- Final release build packaged successfully with the unchanged persistent certificate requirement. Running app reopened with both permissions On.
- Native UI showed only Ask and Show Me. Typing a question without selecting anything enabled Send; test text was cleared.
- User confirmed the new local admin form successfully validated their replacement key and selected a model. The app's existing saved token returned HTTP 401 from the relay; replacement app token setup is pending user entry. No secrets were printed or copied into chat.

- Live connection confirmed in the running app after the user replaced the access token: Find models loaded openai/gpt-oss-20b, it was selected and saved, and Test connection reported Connected with no screen data sent. Pictures were disabled for this text model. Both permissions remained On. Chat is open and selection overlays are closed for user testing. Full screen-grounded Ask/Show Me remains to be exercised.

## HTTP 502 follow-up

- Reproduced empty visible answers from gpt-oss-20b with synthetic screen-sized context while a small connection prompt succeeded. This reproduces a model failure class; the original failed provider response was not retained.
- Switched the live relay to available qwen/qwen3.8-27b without restarting the relay or exposing/re-entering the developer key. The same larger synthetic request returned a nonempty valid JSON decision. Temporary diagnostic tokens were revoked.
- Compacted model context to visible intersecting controls (10,000-character row budget plus 2,500-character OCR excerpt). Native references and original control IDs remain available for highlighting.
- Provider errors now distinguish auth, quota, redirects, service readiness and unusable upstream answers without displaying raw provider bodies.
- Find models automatically selects an available replacement when the prior model is no longer offered. Updated the next-start local relay preference to the verified Qwen model.
- Seven Swift and eight Node checks passed; release app and archive rebuilt using the same development certificate. Both permissions remained On. Saved qwen/qwen3.8-27b and observed live Connected confirmation inside the app. Pictures remain off. User resumed interacting with chat; UI automation stopped to avoid competing with their testing.

## Local model and selection stall

- Installed qwen3.5:4b (3,973,305,013 bytes) in the user's Ollama model store; it was previously empty. Local Ollama listens on loopback with 8,192-token context. Local requests disable Qwen thinking, and agent decisions request JSON mode.
- Live local Ask and Show Me fixture checks passed in 5.7s (first load) and 1.5s. The running app saved Ollama/local model and confirmed Connected. No automatic cloud fallback is configured.
- During user's selection test, Howdoey became unresponsive. Sampling found its main thread spending every sample in SwiftUI layout negotiation, not AX inspection, OCR or model calls. Process CPU remained about 100%, with excessive memory usage.
- Replaced the root conditional safeAreaInset with a bounded VStack using the native panel's concrete width/height. After rebuild, a real capture plus local answer completed in about five seconds; idle CPU dropped to about 1%, RSS about 123 MB. This verifies the observed stall fix, not a universal latency guarantee.
- The test also caught a system-process target (loginwindow); default context now filters nonregular/system apps and observation refuses to substitute an entire desktop when no target window exists. Added cancellation checks between capture and OCR stages.
- Additional native TextEdit fixture automation did not reliably make that app frontmost; one earlier local response incorrectly called the chat transcript a recipe. Local fixture checks are not proof of general model answer accuracy.

## Quiet target highlights

- Removed the running renderer’s animated cursor, filled large target marker, separate floating caption and 440×220 progress panel. A native thin-outline view surrounds the target, with a short opacity transition and compact Check progress/Stop controls.
- Replaced the running selection surface with an undimmed canvas: only the dragged rectangle/hovered window gets a thin border, plus a short hint and Cancel. Explicit selection stays optional.
- Model context marks only small, visible, eligible controls as highlightable. Runtime policy rejects large containers before showing the assistant’s step. Native controls are re-resolved by exact role/label and nearby position; ambiguous or moved controls stop without pointing. OCR targets require a recent capture and unchanged window frame.
- Recent conversation is included in submitted requests, so short follow-ups can refer to the previous question and answer.
- Eight Swift checks and eight Node tests passed. Three live local-model checks passed: Ask, Show Me targeting the observed Dark control, and a missing Compose button that must return wait. These fixture checks do not certify every Gmail layout or model answer.

- Rebuilt and reopened the signed app. The quiet selection surface exposed only its short hint and Cancel control; Escape returned immediately to the ready chat. No selection or guide overlay was left active. Full Gmail target accuracy still requires hands-on retesting; the missing-target fixture and geometry guard are the verified protections.

## Target lookup recovery

- The displayed “control is no longer available” error came from the strict valid-target ID check. Added targetLabel to model actions and a resolver that accepts an exact current ID/label, or repairs a wrong ID using an exact unique eligible label. Missing/ambiguous labels do not resolve.
- Invalid/moved targets and nonfinal responses without an action now cause up to two fresh observations and model retries. Unverified instructions are withheld until the guide can be placed. Exhaustion reports the missing target in plain language and leaves no highlight.
- Highlightable controls are serialized before other context so their IDs/labels are less likely to be omitted by the input budget. AX traversal prioritizes the focused field and its ancestors and filters off-window controls. This helps busy compose windows without browser-specific automation.
- Nine Swift and eight Node checks passed, including wrong-ID repair and ambiguity refusal. Three local-model fixture checks passed. The missing-control fixture accepts either wait or no action; the small model sometimes returns no action despite the requested schema, which the app now handles with bounded refresh rather than a technical error.

## Final UI recovery and live smoke test

- Reproduced another main-thread UI freeze when a long assistant reply and guide appeared together. Removed SwiftUI native text-selection overlays from chat bubbles, replaced LazyVStack with a plain bounded stack, and deferred nonanimated scrolling. Permission polling publishes only actual changes. Chat response and later guide/Stop tests remained responsive around 0.3% idle CPU.
- Step presentation now uses an AppKit instruction card with the exact target name, short readable instruction, Check progress and Stop. Main chat hides during a pointed step, returning on completion/failure or native-card Stop. The card is placed beside the target rather than at an unrelated bottom corner.
- Screenshot capture now uses the selected/frontmost CGWindow ID instead of choosing a same-sized window by maximum intersection. AX lookup prefers that window's title and preserves its window element, which is raised for guidance. Focused-element traversal is used only for the selected AX window. This addresses contradictory AX/screenshot context with multiple Chrome windows.
- Live Ask completed and the panel remained responsive. The final live Show Me request identified an actually observed 'Back to setup' link in the selected ChatGPT window; the native card visibly displayed that target and a matching instruction. Clicking the native Stop button cleared the guide and returned to a responsive chat. No underlying target button/link was clicked.
- Nine core checks, eight Node checks and three local-model protocol fixtures passed on the current code. App/ZIP rebuilt with the persistent local certificate. This is a local testing build; Gmail attachment flow and automatic progress verification still need user testing and are not claimed universally reliable.
- Automated attempts to select the separate Chrome fixture were affected by foreground-window differences; do not present them as a completed Gmail or file-picker workflow. The native guide's screenshot and Stop action are the verified UI handoff evidence.

## Claude Code / Haiku demo iteration — Oct 25

- Installed Claude Code 2.1.310 is signed in. Actual `claude-haiku-5-5`
  connection returned OK; the loopback demo bridge now explicitly selects it.
- Howdoey's in-app connection test succeeded through the bridge. A real captured
  Chrome GitHub page was understood; Show Me produced a validated compact outline
  for the actual Add file website button. Nothing was clicked on the website.
  This is not evidence that Gmail's entire attachment workflow is verified.
- The previous blank selection preview was visually confirmed. Capture now takes
  the full target window without sourceRect, excludes window shadows, and crops
  the resulting pixels. The next real app preview showed the full Chrome page.
- Chrome AX now requests EnhancedUserInterface and discovers web areas before
  spending its detailed traversal budget on browser chrome. Detailed scans use
  lazy labels, fewer unnecessary attribute calls, and increased web nesting depth.
- Selection mode: blue 12% tint, centered instructions 68pt below screen top,
  Cancel alongside instructions. Visually inspected; clicking Cancel returned
  the app to Ready. No selection overlay remains active at handoff.
- Model decisions optionally predict a relevant progress signal. Two matching
  local AX observations trigger fresh model verification; unrelated changes do
  not trigger it. Manual Check progress remains a fallback. AX polling now runs
  off the main thread. Actual complete Gmail automatic progression still needs
  the user's test; prediction absence or unsupported controls can require manual
  checking. No autonomous clicks, typing, sending, uploads or file changes.
- 20 automated checks passed (10 Swift, 8 relay, 2 Claude bridge). Stable signed
  app and ZIP rebuilt. Public Developer ID signing/notarization still required.

## Gmail visibility and Mail window transitions

- Confirmed the original Gmail paperclip failure: the actual Attach files AX
  control was found locally but omitted from the bounded model context. Buttons,
  popups and fields now precede inbox checkboxes/static text; row/cell/container
  duplication is removed and the context budget is 20,000 characters. Focused
  subtrees are scanned before the rest of the page.
- Live real-Gmail observation through the signed app captured the open draft,
  found Attach files at a compact 20x20 frame, included it in the provider
  request, and Haiku returned that exact valid target. No attachment was clicked
  or uploaded during this model test.
- Confirmed Mail progress was pinned to the original window ID/title. Each new
  observation now follows the focused window of the same application. A changed
  AX window is also an automatic verification signal after two observations.
  A single screenshot/control list remains bound to one window.
- Native Mail test: opened an empty New Message, captured the new compose window
  rather than Inbox, then closed that untouched test draft. Full automatic
  multi-step Mail UI progression is still not verified: CUA interaction and the
  physically foreground app differed during the attempted test. User retest
  remains necessary; do not claim the entire automatic workflow passed.
- Diagnostic capture is off at handoff. Temporary diagnostic screenshots and
  metadata were removed. No website files changed.
