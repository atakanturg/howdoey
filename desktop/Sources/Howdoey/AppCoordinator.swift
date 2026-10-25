import AppKit
import SwiftUI
import Carbon
import Combine
import HowdoeyCore

@main struct HowdoeyLauncher {
    static func main() {
        let app = NSApplication.shared
        if [3,4,5].contains(CommandLine.arguments.count), CommandLine.arguments[1] == "--inspect-capture" {
            let bundleID = CommandLine.arguments[2]
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do {
                    guard let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { throw AgentError.invalid("Target application is not running") }
                    let infos = CGWindowListCopyWindowInfo([.optionAll,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
                    let hint = CommandLine.arguments.count >= 4 ? CommandLine.arguments[3] : ""
                    let selectedID = infos.first { ($0[kCGWindowOwnerPID as String] as? Int32) == target.processIdentifier && !hint.isEmpty && (($0[kCGWindowName as String] as? String)?.localizedCaseInsensitiveContains(hint) == true) }.flatMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
                    let observation = try await Observer().observe(app: target, windowID: selectedID)
                    print("Capture inspected: \(observation.jpeg?.count ?? 0) JPEG bytes; \(observation.ax.controls.count) controls; \(NSStringFromRect(observation.region))")
                    let labels = observation.ax.controls.filter { ["Attach files","Message Body","Subject"].contains($0.label) }.map { "\($0.label): \(NSStringFromRect($0.frame))" }
                    print(labels.joined(separator: "\n"))
                    print("Attachment control included in model context: \(observation.text.contains("Attach files"))")
                    if CommandLine.arguments.last == "--test-model" {
                        guard let data = UserDefaults.standard.data(forKey:"providerConfiguration") else { throw AgentError.invalid("No configured provider") }
                        let config = try JSONDecoder().decode(ProviderConfiguration.self,from:data)
                        let prompt = AgentPrompt.user(mode:.show,goal:"Show me how to attach an image to the email draft already open.",observation:observation,history:[],previous:nil,fileContext:"The user clicks. Do not send or change the email.")
                        let raw = try await ProviderClient().complete(configuration:config,key:"",system:AgentPrompt.system,user:prompt,jpeg:observation.jpeg,jsonDecision:true)
                        let decision = try Decision.parse(raw)
                        let candidates = observation.ax.controls.filter { $0.isGuideTarget(in:observation.region) }
                        guard let action = decision.action, let resolved = GuideTargetResolver.resolve(action,candidates:candidates.map { GuideCandidate(id:$0.id,label:String($0.label.prefix(160))) }),
                              let selected = candidates.first(where: { $0.id == resolved.target }) else { throw AgentError.invalid("Model did not identify a valid current control") }
                        print("Live model target: \(selected.label); \(NSStringFromRect(selected.frame)); progress: \(decision.progress?.kind.rawValue ?? "manual")")
                    }

                } catch { print("Capture inspection failed: \(error.localizedDescription)") }
                app.terminate(nil)
            }
            app.run(); return
        }
        let delegate = AppCoordinator()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
// An activating main window is intentional: a non-activating overlay panel can show
// a field caret while keyboard events continue going to the previously active app.
final class ChatWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
@MainActor final class AppCoordinator: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let overlays = OverlayController()
    var panel: NSWindow?
    var statusItem: NSStatusItem?
    var hotKey: GlobalHotKey?
    var lastExternalApp: NSRunningApplication?
    var activationObserver: NSObjectProtocol?
    var phaseSubscription: AnyCancellable?
    var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let app = NSWorkspace.shared.frontmostApplication, Self.isContextApplication(app) { lastExternalApp = app }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in
                guard Self.isContextApplication(app) else { return }
                self?.lastExternalApp = app
            }
        }
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = status.button {
            button.image = Brand.menuBarImage()
            button.target = self; button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Howdoey · Control–Option–Space"
        }
        statusItem = status
        model.defaultTargetHandler = { [weak self] in
            let current = NSWorkspace.shared.frontmostApplication
            if let current, Self.isContextApplication(current) { return current }
            return self?.lastExternalApp
        }
        model.selectionHandler = { [weak self] kind in self?.startSelection(kind) }
        model.showPanelHandler = { [weak self] in self?.showPanel() }
        model.closePanelHandler = { [weak self] in self?.panel?.orderOut(nil) }
        model.demonstrationHandler = { [weak self] target in
            if target == nil { self?.overlays.dismissSelection() }
            if target != nil { self?.panel?.orderOut(nil) }
            self?.overlays.showDemonstration(target)
        }
        hotKey = GlobalHotKey { [weak self] in
            guard let self else { return }
            if model.phase == .selecting { overlays.dismissSelection(); model.selectionCancelled() }
            else { showPanel() }
        }
        phaseSubscription = model.$phase.receive(on: DispatchQueue.main).sink { [weak self] phase in
            guard let self else { return }
            overlays.updateProgressControls(model: model, phase: phase)
            if model.sessionMode == .show, [.observing,.thinking,.demonstrating,.verifying,.complete,.failed].contains(phase) {
                panel?.orderOut(nil)
            }
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseUp,.rightMouseUp,.otherMouseUp]) { [weak self] _ in
            Task { @MainActor in
                guard let self, let target = self.model.targetApp,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else { return }
                self.model.userClickedTargetApp()
            }
        }
        installMenu()
        showPanel()
    }
    private static func isContextApplication(_ app: NSRunningApplication) -> Bool {
        app.processIdentifier != ProcessInfo.processInfo.processIdentifier && !app.isTerminated &&
            app.activationPolicy == .regular &&
            !["com.apple.loginwindow", "com.apple.dock", "com.apple.systemuiserver", "com.apple.controlcenter"].contains(app.bundleIdentifier ?? "")
    }
    private func installMenu() {
        let menu = NSMenu()
        let appMenu = NSMenuItem(); menu.addItem(appMenu)
        let submenu = NSMenu(); appMenu.submenu = submenu
        submenu.addItem(withTitle: "About Howdoey", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Quit Howdoey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(); menu.addItem(edit); edit.submenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.submenu?.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        NSApp.mainMenu = menu
    }
    @objc func togglePanel() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Howdoey", action: #selector(showFromMenu), keyEquivalent: "")
            menu.addItem(withTitle: "Stop current task", action: #selector(stopFromMenu), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Howdoey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
            statusItem?.menu = menu; statusItem?.button?.performClick(nil); statusItem?.menu = nil
        } else if panel?.isVisible == true { panel?.orderOut(nil) } else { showPanel() }
    }
    @objc func showFromMenu() { showPanel() }
    @objc func stopFromMenu() { model.stop(); overlays.dismissSelection(); showPanel() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPanel(); return true }

    func showPanel() {
        if panel == nil {
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            let rect = CGRect(x: visible.maxX - 436, y: max(visible.minY + 16, visible.maxY - 696), width: 420, height: min(680, visible.height - 32))
            let window = ChatWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
            window.title = "Howdoey"; window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
            window.isReleasedWhenClosed = false; window.level = .floating; window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isMovableByWindowBackground = true
            // Claude owns the pure views. Codex owns all running-app windows and hooks.
            // A concrete proposal is required here. An unbounded root plus a conditional
            // safeAreaInset can make SwiftUI repeatedly negotiate the chat's text and
            // screenshot layout, starving capture tasks and Stop on the main thread.
            let content = VStack(spacing: 0) {
                ChatPanelView(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
                RelaySetupNotice(model: model)
            }.frame(width: rect.width, height: rect.height)
            let hosting = NSHostingView(rootView: content)
            hosting.sizingOptions = []
            window.contentView = hosting
            window.setFrame(rect, display: false)
            panel = window
        }
        model.refreshPermissions()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func startSelection(_ kind: SelectionKind) {
        panel?.orderOut(nil)
        overlays.select(kind: kind) { [weak self] region, owner in
            guard let self else { return }
            if kind == .window, let owner, let app = NSRunningApplication(processIdentifier: owner) {
                let mouse = NSEvent.mouseLocation
                let point = CGPoint(x: mouse.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - mouse.y)
                let selectedFrame = region ?? WindowHitTest.topWindow(at: point)?.rect
                app.activate(options: [])
                model.acceptSelection(app: app, region: selectedFrame)
                return
            }
            guard let region else { model.selectionCancelled(); return }
            guard let app = owner.flatMap({ NSRunningApplication(processIdentifier: $0) }) ?? lastExternalApp,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                model.errorMessage = "Select an area inside the application you want help with."
                model.selectionCancelled(); return
            }
            if kind == .element || region.width < 24 || region.height < 16 {
                let selected = region
                let token = model.generation
                model.phase = .observing
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let snapshot = await model.observer.accessibility.snapshotAsync(pid:app.processIdentifier,region:selected)
                    guard model.generation == token else { return }
                    let center = CGPoint(x:selected.midX,y:selected.midY)
                    let match = snapshot.controls.filter { $0.frame.contains(center) && !$0.label.isEmpty }.min { $0.frame.width*$0.frame.height < $1.frame.width*$1.frame.height }
                    let detail = match?.frame.insetBy(dx:-8,dy:-6) ?? selected.insetBy(dx:-70,dy:-35)
                    model.acceptSelection(app:app,region:detail)
                }
                return
            }
            model.acceptSelection(app: app, region: region)
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }; clickMonitor = nil
        model.stop(); overlays.dismissSelection()
    }
}
@MainActor final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    let fire: () -> Void
    init(fire: @escaping () -> Void) {
        self.fire = fire
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, pointer in
            guard let pointer else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalHotKey>.fromOpaque(pointer).takeUnretainedValue()
            DispatchQueue.main.async { owner.fire() }
            return noErr
        }, 1, &event, opaque, &handler)
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x48445759, id: 1), GetApplicationEventTarget(), 0, &ref)
        if status != noErr { NSLog("Howdoey shortcut unavailable; use the menu bar icon.") }
    }
    deinit { if let ref { UnregisterEventHotKey(ref) }; if let handler { RemoveEventHandler(handler) } }
}
