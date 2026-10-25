import AppKit
import HowdoeyCore

@MainActor extension AppModel {
    func restoreSettings() {
        if let data = UserDefaults.standard.data(forKey: "providerConfiguration"), let config = try? JSONDecoder().decode(ProviderConfiguration.self, from: data) { configuration = config }
        let freshInstall = UserDefaults.standard.data(forKey:"providerConfiguration") == nil
        if freshInstall {
            showSettings = true
            if !UserDefaults.standard.bool(forKey:"automaticLocalAISetupStarted") {
                UserDefaults.standard.set(true,forKey:"automaticLocalAISetupStarted")
                downloadLocalAI()
            }
        }
        if !freshInstall && (configuration.endpoint == "http://127.0.0.1:11434/v1" || configuration.endpoint == "http://localhost:11434/v1") {
            Task { try? await LocalAISetup.shared.startInstalledService() }
        }
        apiKeyInput = configuration.endpoint == "http://127.0.0.1:8767/v1" ? "" : KeyStore.read(account: configuration.endpoint)
        if configuration.endpoint.contains(":8767/") { providerPreset = .claudeDemo; settingsStatus = "Claude Code demo: screen context is forwarded to Anthropic using your Claude account. No API key needed." }
        else if configuration.endpoint.contains(":8766/") { providerPreset = .shared }
        else if configuration.endpoint.contains("localhost") || configuration.endpoint.contains("127.0.0.1") { providerPreset = .ollama }
        else if configuration.endpoint.contains("api.groq.com") { providerPreset = .groq }
        else { providerPreset = .custom }
    }
    func applyProviderPreset() {
        guard !isBusy else { return }
        switch providerPreset {
        case .shared: configuration.endpoint = "http://127.0.0.1:8766/v1"
        case .claudeDemo: configuration.endpoint = "http://127.0.0.1:8767/v1"
        case .groq: configuration.endpoint = "https://api.groq.com/openai/v1"
        case .ollama: configuration.endpoint = "http://localhost:11434/v1"
        case .custom: break
        }
        configuration.model = ""; availableModels = []
        apiKeyInput = configuration.endpoint == "http://127.0.0.1:8767/v1" ? "" : KeyStore.read(account: configuration.endpoint)
        settingsStatus = "Load models, choose one, then test the connection. Images need a vision-capable model."
    }
    func saveSettings() {
        do {
            _ = try Policy.endpoint(configuration.endpoint)
            try KeyStore.write(apiKeyInput, account: configuration.endpoint)
            UserDefaults.standard.set(try JSONEncoder().encode(configuration), forKey: "providerConfiguration")
            settingsStatus = providerPreset == .shared ? "Saved. Your Howdoey access token is in Keychain. The developer Groq key stays on the relay server." : "Saved. API key is stored in macOS Keychain."
        } catch { settingsStatus = error.localizedDescription }
    }
    func fetchModels() {
        guard !isCheckingProvider else { return }
        isCheckingProvider = true; settingsStatus = "Loading models…"
        let config = configuration; let key = apiKeyInput
        Task {
            defer { isCheckingProvider = false }
            do {
                let models = try await provider.models(configuration: config, key: key)
                guard configuration.endpoint == config.endpoint else { return }
                availableModels = models
                if !models.contains(configuration.model) { configuration.model = models.first ?? "" }
                settingsStatus = models.isEmpty ? "No models found. Pull a model in Ollama or check your provider account." : "Choose a chat model. Enable screenshots only with a vision-capable model."
            } catch { settingsStatus = error.localizedDescription }
        }
    }
    func testProvider() {
        guard !isCheckingProvider else { return }
        isCheckingProvider = true; settingsStatus = "Testing without screen data…"
        let config = configuration; let key = apiKeyInput
        Task {
            defer { isCheckingProvider = false }
            do {
                _ = try await provider.complete(configuration: config, key: key, system: "You are a connection test. Reply with OK.", user: "Connection test. No screen data is included.")
                settingsStatus = config.endpoint.contains(":8767/") ? "Connected to Claude Code. Screen context goes to Anthropic using your Claude account. No screen data was sent in this test." : "Connected to \(config.model). No screen data was sent in this test."
            } catch { settingsStatus = error.localizedDescription }
        }
    }
    func refreshPermissions() {
        let current = PermissionState(accessibility: AccessibilityService.trusted, screenRecording: CGPreflightScreenCaptureAccess())
        if current != permissions { permissions = current }
    }
    func requestAccessibility() { AccessibilityService.request(); refreshPermissions() }
    func requestScreenRecording() { _ = CGRequestScreenCaptureAccess(); refreshPermissions() }
    func openAccessibilitySettings() { openSettings("Privacy_Accessibility") }
    func openScreenRecordingSettings() { openSettings("Privacy_ScreenCapture") }
    private func openSettings(_ page: String) { if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(page)") { NSWorkspace.shared.open(url) } }

    func selectRegion() { beginSelection(.region) }
    func selectElement() { beginSelection(.element) }
    func selectWindow() { beginSelection(.window) }
    private func beginSelection(_ kind: SelectionKind) {
        stopWork(); errorMessage = nil
        refreshPermissions()
        guard permissions.screenRecording || permissions.accessibility else {
            errorMessage = "Enable Screen Recording for area selection, or Accessibility for native window inspection."
            showSettings = true; return
        }
        phase = .selecting; selectionHandler?(kind)
    }
    func acceptSelection(app: NSRunningApplication, region: CGRect?) {
        stopWork(); let token = generation
        selectionIsExplicit = true
        targetApp = app; targetWindowID = nil; phase = .observing; targetApplication = app.localizedName ?? "Application"
        task = Task {
            do {
                let observed = try await observer.observe(app: app, region: region)
                guard generation == token, !Task.isCancelled else { return }
                observation = observed; targetWindowID = observed.windowID; selectionImage = observed.image
                selectionDescription = region == nil ? "Current window in \(observed.appName)" : "Selected area in \(observed.appName)"
                phase = .idle; showPanelHandler?()
                if observed.ax.controls.isEmpty && observed.jpeg == nil { errorMessage = "No readable context was found. Check permissions and select the app again." }
            } catch { fail(error, token: token) }
        }
    }
    func selectionCancelled() { phase = observation == nil ? .idle : .stopped; showPanelHandler?() }
    func clearSelection() {
        stop(); selectionIsExplicit = false; observation = nil; targetApp = nil; selectionImage = nil; targetApplication = ""
        selectionDescription = "Uses your active window unless you select an area"; phase = .idle
    }
    func clearConversation() {
        stopWork()
        conversationID = UUID()
        messages = []; history = []; sessionConversation = ""; sessionGoal = ""; draft = ""
        previousAction = nil; progressExpectation = nil; errorMessage = nil
        stepCount = 0; failureCount = 0; targetRefreshCount = 0
        selectionIsExplicit = false; observation = nil; selectionImage = nil
        targetApp = nil; targetWindowID = nil; targetApplication = ""
        showSettings = false; phase = .idle
        showPanelHandler?()
    }
    func closePanel() { stop(); closePanelHandler?() }
    private func stopWork() {
        generation = UUID(); task?.cancel(); task = nil; progressTask?.cancel(); progressTask = nil
        clickCheckTask?.cancel(); clickCheckTask = nil; clickCheckPending = false
        pendingApproval = nil; pendingAction = nil; pendingDestination = nil
        demonstration = nil; demonstrationHandler?(nil); undoPending = false
    }
    func stop() { stopWork(); phase = .stopped }
    func cancelApproval() { stop(); messages.append(.init(role: .system, text: "Cancelled. No pending action was performed.")) }

    func submit() {
        mode = .show
        guard canSubmit else { return }
        guard !selectionIsExplicit || observation.map({ Date().timeIntervalSince($0.capturedAt) < 180 }) == true else { errorMessage = "This selection is more than three minutes old. Select it again so I can use current information."; return }
        guard !configuration.model.isEmpty else { showSettings = true; errorMessage = "Choose your AI provider and model first."; return }
        stopWork(); let token = generation
        errorMessage = nil; stepCount = 0; failureCount = 0; targetRefreshCount = 0; previousAction = nil; history = []
        sessionConfiguration = configuration; sessionAPIKey = apiKeyInput
        sessionConversation = messages.suffix(4).map { "\($0.role): \(String($0.text.prefix(800)))" }.joined(separator: "\n")
        sessionGoal = draft.trimmingCharacters(in: .whitespacesAndNewlines); draft = ""; sessionMode = mode
        messages.append(.init(role: .user, text: sessionGoal))
        phase = .observing
        task = Task {
            do {
                if !selectionIsExplicit {
                    guard let app = defaultTargetHandler?(), !app.isTerminated,
                          app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                        throw AgentError.invalid("Open the page or app you want help with, then open Howdoey again.")
                    }
                    targetApp = app; targetWindowID = nil; targetApplication = app.localizedName ?? "Application"
                    try await reobserve(token: token)
                }
                try Task.checkCancellation()
                await decide(token: token)
            } catch is CancellationError { }
            catch { fail(error, token: token) }
        }
    }
    private func decide(token: UUID) async {
        guard generation == token, !Task.isCancelled, let observed = observation else { return }
        defer { scheduleClickCheckIfReady() }
        phase = previousAction == nil ? .thinking : .verifying
        do {
            let user = AgentPrompt.user(mode: sessionMode, goal: sessionGoal, observation: observed, history: history, previous: previousAction, fileContext: "Computer execution is unavailable. The user performs every demonstrated step.", conversation: sessionConversation)
            var requestConfiguration = sessionConfiguration
            requestConfiguration.sendImages = sessionConfiguration.sendImages && configuration.sendImages
            let raw = try await provider.complete(configuration: requestConfiguration, key: sessionAPIKey, system: AgentPrompt.system, user: user, jpeg: observed.jpeg, jsonDecision: true)
            try Task.checkCancellation()
            guard generation == token else { return }
            let decision = try Decision.parse(raw)
            stepCount += 1
            if clickCheckPending {
                clickCheckPending = false
                history.append("A user click happened while the model was responding. Discard that stale decision and inspect the current window.")
                try await reobserve(token:token)
                await decide(token:token)
                return
            }
            if let previousAction, previousAction.kind != .wait {
                if decision.verifiedPrevious != true {
                    failureCount += 1
                    history.append("Verification was unsuccessful: \(decision.message)")
                    if failureCount >= Policy.maximumFailures {
                        history.append("Several clicks did not produce verified progress. Reassess the current window and ask for missing context if needed; do not repeat an unsuccessful instruction or abandon the user's goal.")
                        failureCount = 0
                    }
                    guard !decision.done else { throw AgentError.invalid("The model could not verify the previous step. I stopped without claiming completion.") }
                } else { failureCount = 0; history.append("Previous step verified against fresh observation.") }
            }
            if sessionMode == .show && !decision.done && decision.action == nil {
                await refreshGuideTarget(token: token); return
            }
            let candidates = observed.ax.controls.filter { $0.isGuideTarget(in: observed.region) }
            var resolvedAction = decision.action
            if let action = decision.action {
                guard let resolved = GuideTargetResolver.resolve(action, candidates: candidates.map { GuideCandidate(id: $0.id, label: String($0.label.prefix(160))) }) else {
                    await refreshGuideTarget(token: token); return
                }
                resolvedAction = resolved
                try Policy.validate(resolved, mode: sessionMode, validTargets: Set(candidates.map(\.id)))
            }
            progressExpectation = decision.progress
            // Do not show a confident instruction until its visual target is validated.
            if let action = resolvedAction, action.kind != .wait {
                do { try presentGuide(action: action, observed: observed, caption: decision.message) }
                catch { await refreshGuideTarget(token: token); return }
            }
            messages.append(.init(role: .assistant, text: decision.message))
            if decision.done {
                phase = .complete; demonstration = nil; demonstrationHandler?(nil); return
            }
            guard let action = resolvedAction else { throw AgentError.invalid("The model returned neither an answer nor an actionable next step.") }
            if action.kind == .wait { presentManualStep(action: action, observed: observed) }
        } catch is CancellationError { }
        catch { fail(error, token: token) }
    }
    private func refreshGuideTarget(token: UUID) async {
        guard generation == token, !Task.isCancelled else { return }
        guard targetRefreshCount < 2 else {
            demonstration = nil; demonstrationHandler?(nil)
            messages.append(.init(role: .assistant, text: "I couldn’t locate that control. Keep it visible and try again."))
            phase = .failed; return
        }
        targetRefreshCount += 1; phase = .observing
        selectionDescription = "Refreshing the screen to find the right control…"
        history.append("Target could not be located. Use only CURRENT highlightable controls with their exact targetLabel and id. If the needed control is absent, use wait; do not guess or choose a container.")
        do {
            guard let app = targetApp, !app.isTerminated else { throw AgentError.invalid("Open the app you want help with, then ask again.") }
            let region = selectionIsExplicit ? observation?.region : nil
            let fresh = try await observer.observe(app: app, region: region)
            try Task.checkCancellation(); guard generation == token else { return }
            observation = fresh; selectionImage = fresh.image
            selectionDescription = "Current window in \(fresh.appName)"
            await decide(token: token)
        } catch is CancellationError { }
        catch { fail(error, token: token) }
    }
    private func presentManualStep(action: AgentAction, observed: Observation) {
        previousAction = action; guideFingerprint = fingerprint(observed)
        phase = .demonstrating; demonstration = nil; demonstrationHandler?(nil)
        startProgressWatch()
    }
    private func presentGuide(action: AgentAction, observed: Observation, caption: String) throws {
        guard let id = action.target, let control = observed.ax.controls.first(where: { $0.id == id }) else {
            presentManualStep(action: action, observed: observed); return
        }
        guard control.isGuideTarget(in: observed.region) else {
            throw AgentError.invalid("I couldn't identify a small, visible control for this step. Ask again with the relevant window open.")
        }
        try observer.accessibility.activate(pid: observed.pid)
        if let window = observed.ax.windowElement { _ = AXUIElementPerformAction(window,kAXRaiseAction as CFString) }
        let baseline = observer.accessibility.snapshot(pid: observed.pid, region: observed.region, windowTitle: observed.ax.windowTitle)
        let targetRect: CGRect
        if control.role == "OCRText" {
            guard Date().timeIntervalSince(observed.capturedAt) < 20,
                  baseline.windowFrame == observed.ax.windowFrame else {
                throw AgentError.invalid("The window changed while I was finding that control. Ask again so I can locate it accurately.")
            }
            targetRect = control.frame
        } else {
            let matches = baseline.controls.filter {
                $0.role == control.role && $0.label == control.label && $0.isGuideTarget(in: observed.region) &&
                abs($0.frame.midX - control.frame.midX) < 40 && abs($0.frame.midY - control.frame.midY) < 40
            }
            guard matches.count == 1, let fresh = matches.first else {
                throw AgentError.invalid("That control moved or is ambiguous. Ask again with the relevant window open.")
            }
            targetRect = fresh.frame
        }
        previousAction = action
        guideFingerprint = baseline.controls.map { "\($0.role)|\($0.label)|\($0.value)|\($0.frame)" }.joined(separator: "\n")
        let target = DemonstrationTarget(rect: targetRect, caption: caption, label: control.label)
        demonstration = target; phase = .demonstrating
        demonstrationHandler?(target)
        startProgressWatch()
    }
    private func fingerprint(_ observed: Observation) -> String {
        observed.ax.controls.map { "\($0.role)|\($0.label)|\($0.value)|\($0.frame)" }.joined(separator: "\n")
    }
    private func progressValues(_ snapshot: AXSnapshot) -> [String:String] {
        var result: [String:String] = [:]
        for control in snapshot.controls where control.enabled && !control.label.isEmpty {
            result[control.label] = control.value
        }
        return result
    }
    private func startProgressWatch() {
        progressTask?.cancel()
        let token = generation
        guard let baseline = observation else { return }
        let before = progressValues(baseline.ax)
        // Older providers may omit a prediction. In that case only watch the
        // demonstrated control, rather than treating every page change as progress.
        let expected = progressExpectation ?? previousAction?.targetLabel.map { ProgressExpectation(kind: .disappears, label: $0) }
        progressTask = Task {
            var matches = 0
            for _ in 0..<90 {
                do { try await Task.sleep(nanoseconds: 1_500_000_000) } catch { return }
                guard generation == token, phase == .demonstrating, let app = targetApp else { return }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { continue }
                let snapshot = await observer.accessibility.snapshotAsync(pid: app.processIdentifier)
                guard generation == token, phase == .demonstrating, !Task.isCancelled else { return }
                // Incomplete scans must not turn a missing control into a false signal.
                guard !snapshot.controls.isEmpty else { matches = 0; continue }
                let windowChanged: Bool
                if let old = baseline.ax.windowElement, let current = snapshot.windowElement { windowChanged = !CFEqual(old,current) }
                else { windowChanged = snapshot.windowTitle != baseline.ax.windowTitle }
                let relevant = windowChanged || (expected?.shouldObserve(before: before, after: progressValues(snapshot), previousWindow: baseline.ax.windowTitle, currentWindow: snapshot.windowTitle) ?? false)
                matches = relevant ? matches + 1 : 0
                if matches >= 2 {
                    history.append("A new focused window or predicted UI change appeared in two observations. Re-check the current screen; this signal alone does not prove success.")
                    checkProgress(); return
                }
            }
        }
    }
    /// Observe only clicks in the app this session is guiding. No keystrokes or
    /// click coordinates are recorded. Rapid clicks coalesce into a fresh check.
    func userClickedTargetApp() {
        guard sessionMode == .show, [.observing,.thinking,.demonstrating,.verifying].contains(phase) else { return }
        clickCheckPending = true
        scheduleClickCheckIfReady()
    }
    private func scheduleClickCheckIfReady() {
        guard clickCheckPending, phase == .demonstrating else { return }
        clickCheckTask?.cancel()
        let token = generation
        clickCheckTask = Task {
            do { try await Task.sleep(nanoseconds: 650_000_000) } catch { return }
            guard token == generation, canCheckProgress, clickCheckPending else { return }
            clickCheckPending = false
            history.append("The user clicked in the guided application. Inspect the fresh window; a click is not proof of success.")
            checkProgress()
        }
    }
    func submitGuideQuestion(_ text: String) {
        let question = text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        stop()
        selectionIsExplicit = false
        mode = .show; draft = question
        submit()
    }
    func checkProgress() {
        guard canCheckProgress else { return }
        clickCheckTask?.cancel(); clickCheckTask = nil; clickCheckPending = false
        progressTask?.cancel(); demonstration = nil; demonstrationHandler?(nil)
        let token = generation
        phase = .verifying
        task = Task {
            do { try await reobserve(token: token); await decide(token: token) }
            catch is CancellationError { }
            catch { fail(error, token: token) }
        }
    }
    private func reobserve(token: UUID) async throws {
        guard let app = targetApp, !app.isTerminated else { throw AgentError.invalid("The target app closed. Select another window.") }
        // A progress check is a NEW observation. Compose windows and file pickers
        // must replace the previous window; only a single observation stays pinned.
        let observed = try await observer.observe(app: app)
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        observation = observed; targetWindowID = observed.windowID; selectionImage = observed.image
        selectionDescription = "Current window in \(observed.appName)"
    }
    // Compatibility for the presentation contract. Computer execution is disabled.
    func approve() { stop() }
    private func fail(_ error: Error, token: UUID) {
        guard generation == token else { return }
        pendingApproval = nil; pendingAction = nil; pendingDestination = nil
        demonstration = nil; demonstrationHandler?(nil); progressTask?.cancel()
        errorMessage = error.localizedDescription; phase = .failed
    }
}
