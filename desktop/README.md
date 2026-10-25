# Howdoey desktop — local iteration 0.1

A native Swift/SwiftUI menu bar assistant for macOS 14+. Website files live separately; everything for this app stays inside `desktop/`.

## Run the first build

From the repository root:

```sh
desktop/scripts/check.sh
desktop/scripts/package.sh
desktop/scripts/run.sh
```

The app is `desktop/dist/Howdoey.app`. The downloadable archive is `desktop/dist/Howdoey-macOS-arm64.zip` on this Apple Silicon Mac. You can drag the app into Applications. Keep one copy in a stable location for permissions; quit the old copy before rebuilding or moving it. Rebuilding the ad-hoc signature can require reauthorizing macOS permissions.

Howdoey has no Dock icon. Click its **Howdoey menu bar logo**, or press **Control–Option–Space**. Right-click the menu bar icon for Stop and Quit. The shortcut is fixed in this iteration; if another app owns it, use the icon.

## Permissions

Open the gear in Howdoey:

- **Accessibility** lets it inspect native controls and locate demonstration targets. Use Ask macOS, then enable Howdoey under System Settings → Privacy & Security → Accessibility.
- **Screen Recording** lets it capture the selected area and run OCR. Enable Howdoey under Privacy & Security → Screen & System Audio Recording (the label varies by macOS version). Quit and reopen if macOS requires it.

No permissions are granted automatically. A missing permission produces an explanation; Howdoey never substitutes a fabricated observation. Native inspection can work without capture; OCR can work without native inspection. Reliable Show Me benefits from Accessibility.

## Choose a real model

No API key or default model ID is embedded.

### Groq

Choose Groq, enter your key, click **Find models**, select an available chat model and **Save**. Use **Test connection** to send a small connection check without any screen data. Turn on screenshots only with a model that supports images. Current IDs vary; use the live model list and [Groq's vision documentation](https://console.groq.com/docs/vision) to confirm image support.

### Ollama on this Mac

Start the installed Ollama application/server and make sure a suitable chat model is installed. Select Ollama in Howdoey; its base URL is `http://localhost:11434/v1`. Find models, select one, Save, and Test connection. No API key is required. Model downloads can be large; Howdoey does not download them or start an inference server automatically. Image sharing needs a vision-capable model. See [Ollama's compatible API](https://docs.ollama.com/api/openai-compatibility).

Custom providers must implement `/models` and `/chat/completions`. Only HTTPS is accepted remotely; HTTP is allowed on loopback. Redirects are refused to avoid forwarding keys or screen data to an unexpected host. Some models do not reliably follow the decision JSON format; unsupported output stops the session with an error.

API keys are stored in macOS Keychain when Save is pressed. Endpoint/model/image preferences use UserDefaults. Selection, OCR, conversation, file choices and screenshots remain in memory. No screen history or telemetry is written by Howdoey. The provider has its own retention policies.

**Image sharing defaults off.** Your question, selected Accessibility labels/values and OCR text are sent even with images off. On subsequent Show Me steps, the app reads the target application's current window to verify and plan. Images of those later windows are also sent if image sharing is enabled. The settings explanation and this README apply to the whole session, not only the initial rectangle. Do not select sensitive content. Secure Accessibility text fields are omitted; images/OCR are withheld when a detected secure field intersects the selected region. Custom-rendered password fields and other private content cannot always be detected.

## Test the two workflows

Selection is optional. Open the page or app you want help with, then open Howdoey and send a question. With no explicit selection, it captures the active application's current visible window at submission. It does not read off-screen browser content. An explicit area/window selection is used until you clear it; clearing returns to automatic window context. The app excludes its own floating panel from target-window captures.

Use disposable data and ordinary, reversible settings while validating this development build.

### Ask

1. Open System Settings → Appearance.
2. Activate Howdoey and select an area around a setting such as Accent color.
3. Choose Ask and enter “What does this setting change?”
4. Confirm the answer refers to your selected label. No computer actions run in Ask.

### Show Me

1. Start in System Settings → Appearance; select a window or the relevant control area.
2. Choose Show Me and ask “Show me how to switch the appearance to Dark.”
3. Howdoey highlights one compact, observed control with a thin outline. Move your own pointer and follow the step.
4. A stable change in native controls triggers a fresh observation and model verification. You may also press Check my progress. Unrelated changes are not proof of success; the model must verify the requested effect.
5. Stop remains available in the floating chat and menu bar. The outline is click-through and never moves your real cursor.

Model accuracy and the controls macOS exposes vary by release. If the target isn't available, the session requests manual help or stops. There is no hardcoded System Settings demonstration.

## Do It: Finder organization and recovery

1. Run `desktop/scripts/demo-fixtures.sh`. This creates a **new unique temporary directory**, a `receipt.txt` in Inbox, and an existing Documents folder containing another `receipt.txt`. It opens Inbox in Finder and prints the path.
2. Activate Howdoey and select the Finder window. Choose Do It.
3. Choose `Inbox/receipt.txt` as the source and the fixture's `Organized` folder as the destination.
4. Ask “Move my chosen file into a Documents folder inside the destination I chose.”
5. Inspect and approve the exact paths. The existing folder is reused; the existing file stays unchanged and the new file becomes `receipt 2.txt`.
6. Native execution checks the source fingerprint, refuses overwriting, and verifies that the source disappeared and destination content matches SHA-256.
7. Show in Finder reveals the result. Undo move previews a separate approval and restores only an unchanged file to an unoccupied original path.

If another app is open, select the intended Finder window; capture is associated with its owning application. The agent can propose opening Finder with approval. If a destination changes after approval, execution rejects the stale preview and re-observes. Each recovery action needs its own approval.

## How it works

- `HowdoeyCore`: structured model decisions, action validation, secure endpoint policy and scoped file operations.
- `Observer`: Accessibility snapshot, target-window ScreenCaptureKit capture, Vision OCR and OCR bounding boxes. Own overlays are excluded.
- `AccessibilityService`: native `AXPress` and `AXSetValue` with PID, current label, geometry and secure-field checks. Does not fall back to blind coordinate clicks or global typing.
- `AppModel`: Observe → Plan → one approved Act → fresh Observe → Verify. Maximum 12 model steps and 3 failed verifications/recovery attempts. Cancellation invalidates in-flight results and cancels URLSession requests via Swift task cancellation.
- `AppCoordinator`: menu bar, Carbon hotkey, panel and overlay lifecycle.
- `UI/`: Claude-owned SwiftUI views, integrated by Codex. `UIHost` and UI-owned controllers are optional helpers; the running application uses Codex's coordinator and the pure UI views to avoid competing lifecycle owners.

The app offers Ask and Show Me only. It explains and points while the user performs every step. It does not execute model-requested clicks, typing, app launches, or file operations. The old file organizer remains a tested core utility, but is disconnected from the running app. Screen content is treated as untrusted input.

## Automated validation

`desktop/scripts/check.sh` runs a dependency-free Swift assertion executable and builds the native app. Full Xcode/XCTest is not installed on this machine, so checks use the Swift Command Line Tools alone. Checks cover Ask action denial, stale target IDs, unsupported applications, path traversal, insecure URLs, malformed model decisions, existing-folder/collision recovery, changed source files, and symlink escape.

Compilation and these tests do **not** prove end-to-end provider accuracy or TCC-gated actions. Grant permissions and configure a real model, then use the manual workflows above. The app never ships mock provider responses. UI preview fixtures are isolated from the running app.

## Packaging and public releases

The packaging script builds for the host architecture and ad-hoc signs the bundle so it runs locally. This is **not** a Developer ID signature, not notarized, and not a production-ready public download. Gatekeeper may block a quarantined unsigned/ad-hoc build on another Mac. Do not tell users to disable Gatekeeper.

For public distribution you need Apple Developer Program membership, a Developer ID Application certificate and notarization credentials. Build with:

```sh
HOWDOEY_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' desktop/scripts/package.sh
xcrun notarytool submit desktop/dist/Howdoey-macOS-arm64.zip --keychain-profile HOWDOEY_NOTARY --wait
xcrun stapler staple desktop/dist/Howdoey.app
xcrun stapler validate desktop/dist/Howdoey.app
spctl --assess --type execute --verbose desktop/dist/Howdoey.app
```

After notarization succeeds and stapling/assessment pass, recreate the ZIP from the stapled app and regenerate its checksum. Full Xcode/additional developer tools may be required for notarization on this machine. Never embed signing credentials. Intel builds require an x86_64 build or a verified universal binary. This iteration produces Apple Silicon output only. The partner's site can eventually link the verified release archive at howdoey.com; no site or hosting changes are made here.

## Known limits

- Local alpha, not a validated general-purpose autonomous agent.
- Computer execution is unavailable. No arbitrary coordinates, keyboard shortcuts, drag/drop, browser DOM automation, unrestricted file management, authentication, payments, messages, or destructive operations.
- Some apps expose incomplete native controls. OCR targets can be pointed to in Show Me.
- The screen selection is one display at a time. Target-window captures support windows on other displays, but mixed-DPI/multiple-display behavior needs hands-on validation.
- Automatic Show Me progress watches structured changes; OCR-only steps require manual Check my progress. Verification uses the configured model and can be wrong.
- Native AX calls have bounded timeouts; application behavior and rendering delay can still cause stale observations and retries.
- File organization and autonomous control are outside the current app scope.
- No updater, login launch, microphone, speech, account system, crash telemetry or notarized release yet.

### Permission appears On in Settings but Off in Howdoey

First quit and reopen the same app build. If that fails after a rebuild, the Settings entry can refer to an earlier code signature. Remove only the stale Howdoey entry and add the exact current `desktop/dist/Howdoey.app` again; do not reset permissions for unrelated applications. The current app path is `/Users/atakanturgut/Documents/ChatGPT/howdoey/desktop/dist/Howdoey.app`. Complete any Touch ID prompt yourself. Keep the binary unchanged during this process. For repeated development builds, use a stable Apple Development/Developer ID signing identity; this Mac currently has none installed. See [Apple's code-signing requirements explanation](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

## Stable signing for local development

The local build now uses a persistent **Howdoey Local Development** certificate in a dedicated private keychain under `~/Library/Application Support/Howdoey/DevelopmentSigning/`. Its private key is not in the repository or app bundle. The user explicitly authorized a user-domain certificate trust rule restricted to the code-signing policy and `/usr/bin/codesign`; no system-wide or browser root trust was added. The dedicated keychain is in the user's search list so codesign can construct its certificate chain. Generated import PEM/PKCS#12 files are removed after import.

`package.sh` unlocks that keychain via Security APIs without putting its password in shell arguments, and automatically signs with the same certificate. Two independently changed code hashes were signed and verified to have the same designated requirement (`identifier com.howdoey.desktop` plus the certificate root fingerprint). This avoids pinning privacy grants to an ad-hoc code hash on every rebuild. Changing from the old ad-hoc identity to this certificate still requires one fresh permission grant. TCC grants cannot be fabricated or automatically migrated by the app.

To prepare the same workflow on a new development Mac, run `scripts/setup-local-signing.sh`; that creates an identity only. Configuring its restricted local trust requires explicit user approval, followed by `swift scripts/local-signing-keychain.swift trust-for-codesign "$HOME/Library/Application Support/Howdoey/DevelopmentSigning"`. Do not rotate or delete this identity casually, or the permission identity changes again. A new developer machine normally has its own local identity.

If there is no stable identity, packaging now refuses to silently replace an existing test app with another ad-hoc signature. `HOWDOEY_ALLOW_ADHOC_REPLACE=1` is an explicit development override, with the known permission-reset consequence.

This certificate is **only for local development**. Public downloads still require Apple Developer ID signing and notarization. For a public release, supply `HOWDOEY_SIGN_IDENTITY` with the Apple-issued identity; the package script then uses that identity with hardened runtime and timestamping. The script's output tells you which signing mode was used. Apple's [code-signing guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html) distinguishes self-signed development identities from public distribution identities.

## Developer-funded AI

See [relay/README.md](relay/README.md). The local developer setup page is `http://127.0.0.1:8766/admin` while `scripts/run-relay.sh` is running. It keeps the developer Groq key server-side and issues expiring, revocable per-user access tokens. **Howdoey shared AI** in settings uses such a token, not the developer key. There is no publicly deployed relay yet; a localhost service is reachable only on this Mac. Deploy it independently behind HTTPS before inviting users on other computers.

## Local testing without cloud quotas

This Mac has Ollama installed. A local model is a separate download; the first local testing setup uses `qwen3.5:4b` (about 4 GB here). Start the installed engine with `desktop/scripts/run-local-model.sh`, then run `ollama pull qwen3.5:4b` once. The helper binds to loopback, sets an 8,192-token context and disables Ollama cloud support. Keep the engine running during testing. It is not bundled into Howdoey or installed on other users’ Macs automatically.

In Howdoey choose Ollama (local), Find models, select qwen3.5:4b, Save, then Test connection. No API key is needed. Local Qwen requests disable extra thinking; agent requests use JSON mode. The Groq token remains stored under its own endpoint for switching back later. No cloud fallback happens automatically.

Run `python3 desktop/scripts/check-local-model.py` for live Ask/Show Me checks against isolated test UI fixtures. These are genuine model requests through Ollama, separate from the app’s screen capture; they do not send user screen data. Native screen capture and highlighting still require their own app smoke test.

### Claude Code demo provider (this Mac only)

Requires an installed, signed-in `claude` CLI (`claude auth status`). This uses
that person's Claude account and allowance. Screen images, OCR and control labels
are sent to Anthropic; it is not offline. This bridge is for local demo testing,
not a way to distribute one developer subscription to other users.

1. Keep `bash desktop/scripts/run-claude-demo.sh` running in Terminal.
2. Quit Howdoey. Run `swift desktop/scripts/configure-claude-demo.swift`.
3. Reopen `desktop/dist/Howdoey.app`. Settings should show Claude Code (cloud demo),
   `http://127.0.0.1:8767/v1`, model `claude-haiku-5-5`, screenshots enabled. No API key
   needs to be pasted. Use Test connection, then test a visible page.

The loopback bridge requires a private same-user token stored with mode 0600 in
`~/Library/Application Support/Howdoey/ClaudeDemo/token`, rejects browser-origin
requests, disables Claude's tools and MCP servers, skips user/project settings,
and disables session persistence. Prompts and screenshots are not logged by the
bridge. Claude service retention/account policies still apply. Requests time out
at 80 seconds and Stop disconnects the request and terminates its CLI process.
The CLI runs outside the repository and cannot edit the app or website.
Switch back through the existing provider picker for Ollama/Groq. The setup
helper preserves the previous configuration in `claudeDemoPreviousConfiguration`.
The app archive remains a local development build, not notarized for distribution.
