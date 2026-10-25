import AppKit
import ApplicationServices
import HowdoeyCore

struct Control: Codable {
    let id: Int
    let role: String
    let label: String
    let value: String
    let frame: CGRect
    let actions: [String]
    let editable: Bool
    let enabled: Bool
    var inFocusedContext = false
}
struct AXSnapshot: @unchecked Sendable {
    var controls: [Control] = []
    var references: [Int: AXUIElement] = [:]
    var secureFrames: [CGRect] = []
    var windowFrame: CGRect?
    var windowTitle = ""
    var windowElement: AXUIElement?
}
@MainActor final class AccessibilityService {
    nonisolated static var trusted: Bool { AXIsProcessTrusted() }
    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    nonisolated func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }
    nonisolated func string(_ element: AXUIElement, _ key: String) -> String { attribute(element, key).map { String(describing: $0) } ?? "" }
    nonisolated func frame(_ element: AXUIElement) -> CGRect? {
        guard let pos = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(pos) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var dimensions = CGSize.zero
        guard AXValueGetValue(pos as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
    /// Same scan, off the main thread: a full traversal can take over a second and would freeze the UI.
    func snapshotAsync(pid: pid_t, region: CGRect? = nil, windowTitle: String? = nil) async -> AXSnapshot {
        await Task.detached(priority: .userInitiated) { [self] in snapshot(pid: pid, region: region, windowTitle: windowTitle) }.value
    }
    nonisolated func snapshot(pid: pid_t, region: CGRect? = nil, windowTitle: String? = nil) -> AXSnapshot {
        guard Self.trusted else { return AXSnapshot() }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        // Chromium and Electron only build their web accessibility tree when asked. Harmless for other apps.
        _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        var result = AXSnapshot()
        let focused = attribute(app, kAXFocusedWindowAttribute)
        var root = focused.map { $0 as! AXUIElement } ?? app
        let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        if let windowTitle, !windowTitle.isEmpty {
            let matches = windows.filter {
                let title = string($0,kAXTitleAttribute)
                return title == windowTitle || title.hasPrefix(windowTitle + " - ")
            }
            if matches.count == 1 { root = matches[0] }
        } else if let region, frame(root)?.contains(CGPoint(x:region.midX,y:region.midY)) != true,
                  let selected = windows.first(where: { frame($0)?.contains(CGPoint(x:region.midX,y:region.midY)) == true }) { root = selected }
        result.windowFrame = frame(root)
        result.windowTitle = string(root,kAXTitleAttribute)
        result.windowElement = root
        // Start near the user's focused field before traversing a busy whole window.
        // Gmail's compose controls can otherwise fall behind hundreds of inbox rows.
        var queue: [(AXUIElement, Int, Bool)] = []
        // Hit-test the selected detail directly. A filename can sit behind many
        // table rows in traversal order and expose its text through AXValue.
        if let region {
            var hit: AXUIElement?
            if AXUIElementCopyElementAtPosition(app,Float(region.midX),Float(region.midY),&hit) == .success, let hit {
                var node = hit
                for _ in 0..<5 {
                    queue.append((node,0,true))
                    if CFEqual(node,root) { break }
                    guard let parent = attribute(node,kAXParentAttribute) else { break }
                    node = parent as! AXUIElement
                }
            }
        }

        if let focused = attribute(app, kAXFocusedUIElementAttribute) {
            var chain: [AXUIElement] = []
            var node = focused as! AXUIElement
            for _ in 0..<60 {
                chain.append(node)
                if CFEqual(node,root) { break }
                guard let parent = attribute(node,kAXParentAttribute) else { break }
                node = parent as! AXUIElement
            }
            // Chromium web nodes often omit AXWindow. Prove ownership by walking
            // parents instead, so the focused draft's toolbar gets scanned first.
            if chain.contains(where: { CFEqual($0,root) }) {
                queue.append(contentsOf: chain.prefix(6).map { ($0,0,true) })
                for ancestor in chain.prefix(6) {
                    if let children = attribute(ancestor,kAXChildrenAttribute) as? [AXUIElement] {
                        queue.append(contentsOf: children.prefix(80).map { ($0,1,true) })
                    }
                }
            }
        }
        // Find web roots cheaply before spending the detailed-query budget on
        // Chrome's toolbar, tabs and bookmarks. Process page content first.
        var discovery: [(AXUIElement,Int)] = [(root,0)]
        var discoverySeen: Set<CFHashCode> = []
        var webRoots: [AXUIElement] = []
        var discoveryIndex = 0
        let discoveryDeadline = Date().addingTimeInterval(0.6)
        while discoveryIndex < discovery.count && discoveryIndex < 250 && Date() < discoveryDeadline {
            let (node,depth) = discovery[discoveryIndex]; discoveryIndex += 1
            guard discoverySeen.insert(CFHash(node)).inserted else { continue }
            let role = string(node,kAXRoleAttribute)
            if role == "AXWebArea" { webRoots.append(node); continue }
            if depth < 14 && !["AXToolbar","AXMenuBar","AXButton","AXTextField"].contains(role),
               let children = attribute(node,kAXChildrenAttribute) as? [AXUIElement] {
                discovery.append(contentsOf: children.prefix(200).map { ($0,depth+1) })
            }
        }
        var scannedWeb = webRoots.isEmpty
        var scannedChrome = false
        if queue.isEmpty {
            queue.append(contentsOf: webRoots.map { ($0,0,false) }); scannedWeb = true
            if queue.isEmpty { queue.append((root,0,false)); scannedChrome = true }
        }

        var visited: Set<CFHashCode> = []
        let deadline = Date().addingTimeInterval(2.0)
        var index = 0
        while index < 1600 && Date() < deadline {
            if index >= queue.count {
                if !scannedWeb {
                    scannedWeb = true; queue.append(contentsOf: webRoots.map { ($0,0,false) })
                } else if !scannedChrome {
                    scannedChrome = true; queue.append((root,0,false))
                } else { break }
            }
            let (node, depth, inFocus) = queue[index]; index += 1
            guard visited.insert(CFHash(node)).inserted else { continue }
            let role = string(node, kAXRoleAttribute)
            let subrole = string(node, kAXSubroleAttribute)
            let rect = frame(node) ?? .zero
            if subrole == kAXSecureTextFieldSubrole || role == kAXSecureTextFieldSubrole {
                if !rect.isEmpty { result.secureFrames.append(rect) }
                continue
            }
            let scope = region ?? result.windowFrame
            let inScope = scope.map { rect.intersects($0) } ?? true
            if !inScope && !rect.isEmpty && ["AXRow","AXCell","AXStaticText","AXButton","AXLink"].contains(role) { continue }
            var label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].lazy.map { self.string(node, $0) }.first { !$0.isEmpty } ?? ""
            if label.isEmpty && ["AXStaticText","AXTextField","AXCell"].contains(role) { label = string(node,kAXValueAttribute) }
            var actionNames: CFArray?
            if !["AXGroup","AXWebArea","AXStaticText","AXWindow","AXScrollArea","AXRow","AXCell"].contains(role) { AXUIElementCopyActionNames(node, &actionNames) }
            let actions = actionNames as? [String] ?? []
            var settable = DarwinBoolean(false)
            if ["AXTextField","AXTextArea","AXComboBox","AXSlider"].contains(role) { AXUIElementIsAttributeSettable(node, kAXValueAttribute as CFString, &settable) }
            if inScope && (!label.isEmpty || !actions.isEmpty || settable.boolValue) && !rect.isEmpty && result.controls.count < 180 {
                let id = result.controls.count + 1
                let rawValue = string(node, kAXValueAttribute)
                result.controls.append(Control(id: id, role: role, label: String(label.prefix(240)), value: String(rawValue.prefix(350)), frame: rect, actions: actions, editable: settable.boolValue, enabled: (attribute(node, kAXEnabledAttribute) as? Bool) ?? true, inFocusedContext: inFocus))
                result.references[id] = node
            }
            if depth < 40, let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(250).map { ($0, depth + 1, inFocus) })
            }
        }
        return result
    }
    func activate(pid: pid_t) throws {
        guard let app = NSRunningApplication(processIdentifier: pid), app.activate(options: []) else { throw AgentError.invalid("The target application has closed.") }
    }
    func perform(_ action: AgentAction, snapshot: AXSnapshot, expectedPID: pid_t) throws -> String {
        guard Self.trusted else { throw AgentError.invalid("Enable Accessibility in System Settings first.") }
        guard let id = action.target, let element = snapshot.references[id], let control = snapshot.controls.first(where: { $0.id == id }) else { throw AgentError.invalid("The control disappeared. Observe again.") }
        var owner: pid_t = 0
        AXUIElementGetPid(element, &owner)
        let currentlyEnabled = (attribute(element, kAXEnabledAttribute) as? Bool) ?? true
        let currentSubrole = string(element, kAXSubroleAttribute)
        guard currentSubrole != kAXSecureTextFieldSubrole else { throw AgentError.invalid("Secure fields cannot be controlled by Howdoey.") }
        guard owner == expectedPID, control.enabled, currentlyEnabled else { throw AgentError.invalid("The target is unavailable or disabled.") }
        guard let currentFrame = frame(element), abs(currentFrame.midX - control.frame.midX) < 5, abs(currentFrame.midY - control.frame.midY) < 5 else { throw AgentError.invalid("The control moved while awaiting approval. Observe again.") }
        let currentLabel = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].map { string(element, $0) }.first { !$0.isEmpty } ?? ""
        guard String(currentLabel.prefix(240)) == control.label else { throw AgentError.invalid("The control changed while awaiting approval. Observe again.") }
        try activate(pid: expectedPID)
        let status: AXError
        if action.kind == .press {
            guard control.actions.contains(kAXPressAction) else { throw AgentError.invalid("This control does not support a native press. Use Show Me to follow it manually.") }
            status = AXUIElementPerformAction(element, kAXPressAction as CFString)
        } else {
            guard control.editable else { throw AgentError.invalid("This field cannot be edited with Accessibility.") }
            // Focus is best-effort; AXSetValue is addressed to the exact element, never the global keyboard.
            _ = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            status = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, (action.value ?? "") as CFString)
        }
        guard status == .success else { throw AgentError.invalid("macOS refused that native action (AX \(status.rawValue)). Re-observe and try another control.") }
        if action.kind == .setValue {
            guard string(element, kAXValueAttribute) == action.value else { throw AgentError.invalid("The field did not retain the requested text.") }
        }
        return "Native \(action.kind.rawValue) delivered to \(control.label). Verify its effect in the next observation."
    }
}

func cocoaRect(_ rect: CGRect) -> CGRect {
    let top = NSScreen.screens.first?.frame.maxY ?? 0
    return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
}
// Reflecting a rectangle around the primary display's horizontal axis is its own
// inverse: top - (top - rect.maxY + rect.height) == rect.minY.
// Both coordinate spaces use points, including on Retina and secondary displays.
func quartzRect(_ rect: CGRect) -> CGRect { cocoaRect(rect) }

extension Control {
    func isGuideTarget(in viewport: CGRect) -> Bool {
        let roles: Set<String> = ["AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXMenuItem", "AXLink", "AXTextField", "AXComboBox", "AXDisclosureTriangle", "AXSwitch", "AXSlider", "AXStaticText", "OCRText", "AXCloseButton"]
        return enabled && roles.contains(role) && (!label.isEmpty || role == "AXCloseButton") && GuideGeometry.isCompactTarget(frame, in: viewport)
    }
}
