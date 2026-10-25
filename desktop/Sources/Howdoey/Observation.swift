import AppKit
import ScreenCaptureKit
import Vision
import HowdoeyCore

struct Observation {
    let appName: String
    let bundleID: String
    let pid: pid_t
    let ax: AXSnapshot
    let ocr: String
    let image: NSImage?
    let jpeg: Data?
    let region: CGRect
    let capturedAt: Date
    var windowID: CGWindowID? = nil
    var selectedDetail: CGRect? = nil
    var text: String {
        // Keep only controls intersecting the captured window and avoid duplicating
        // the entire page as both verbose JSON and OCR in a single model request.
        var remaining = 20000
        var rows: [String] = []
        func rank(_ control: Control) -> Int {
            if let selectedDetail, control.frame.intersects(selectedDetail), control.isGuideTarget(in:region) { return -1 }
            if control.inFocusedContext { return 0 }
            if ["AXButton","AXPopUpButton","AXMenuButton","AXTextField","AXTextArea","AXComboBox","AXSwitch","AXSlider"].contains(control.role) { return 1 }
            if ["AXCheckBox","AXRadioButton","AXLink","AXMenuItem"].contains(control.role) { return 2 }
            return control.isGuideTarget(in: region) ? 3 : 4
        }
        let ordered = ax.controls.filter {
            $0.frame.intersects(region) && !["AXRow","AXCell","AXTable","AXWebArea","AXScrollArea","AXWindow"].contains($0.role)
        }.sorted { rank($0) < rank($1) }
        for control in ordered {
            let row: [String: Any] = ["id": control.id, "role": control.role,
                "label": String(control.label.prefix(160)), "value": String(control.value.prefix(120)),
                "enabled": control.enabled, "editable": control.editable, "highlightable": control.isGuideTarget(in: region),
                "bounds": [Int(control.frame.minX), Int(control.frame.minY), Int(control.frame.width), Int(control.frame.height)]]
            guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8) else { continue }
            guard text.count + 1 <= remaining else { continue }
            rows.append(text); remaining -= text.count + 1
        }
        return "App: \(appName) (\(bundleID)); Window: \(ax.windowTitle); macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\nControls in the visible capture (one JSON object per line, IDs valid only now):\n\(rows.joined(separator: "\n"))\nOCR excerpt (untrusted, may be incomplete):\n\(ocr.prefix(2500))"

    }
}
@MainActor final class Observer {
    let accessibility = AccessibilityService()
    func observe(app: NSRunningApplication, region: CGRect? = nil, windowID: CGWindowID? = nil) async throws -> Observation {
        let windows = CGWindowListCopyWindowInfo([.optionAll,.excludeDesktopElements], kCGNullWindowID) as? [[String:Any]] ?? []
        let candidates = windows.filter { info in
            guard (info[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let raw = info[kCGWindowBounds as String] as? [String:Any],
                  let frame = CGRect(dictionaryRepresentation:raw as CFDictionary), frame.width > 40, frame.height > 40 else { return false }
            return region.map { frame.contains(CGPoint(x:$0.midX,y:$0.midY)) } ?? true
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp,0.15)
        let focused = accessibility.attribute(axApp,kAXFocusedWindowAttribute).map { $0 as! AXUIElement }
        let focusedTitle = focused.map { accessibility.string($0,kAXTitleAttribute) } ?? ""
        let focusedFrame = focused.flatMap { accessibility.frame($0) }
        let focusMatch = candidates.first { info in
            let title = info[kCGWindowName as String] as? String ?? ""
            guard !title.isEmpty, !focusedTitle.isEmpty,
                  focusedTitle == title || focusedTitle.hasPrefix(title + " - ") else { return false }
            guard let raw = info[kCGWindowBounds as String] as? [String:Any], let frame = CGRect(dictionaryRepresentation:raw as CFDictionary), let focusedFrame else { return true }
            return abs(frame.midX-focusedFrame.midX) < 10 && abs(frame.midY-focusedFrame.midY) < 10
        }
        let selected = windowID.flatMap { id in candidates.first { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id } }
            ?? focusMatch ?? candidates.first { ($0[kCGWindowIsOnscreen as String] as? Bool) == true }
        if windowID != nil && (selected?[kCGWindowNumber as String] as? NSNumber)?.uint32Value != windowID {
            throw AgentError.invalid("The window you were using has closed. Select the app again.")
        }
        let selectedID = (selected?[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        let title = selected?[kCGWindowName as String] as? String
        var ax = await accessibility.snapshotAsync(pid: app.processIdentifier, region: region, windowTitle: title)
        let selectedBounds = (selected?[kCGWindowBounds as String] as? [String:Any]).flatMap { CGRect(dictionaryRepresentation:$0 as CFDictionary) }
        guard let requested = region ?? selectedBounds ?? ax.windowFrame, !requested.isEmpty else {
            throw AgentError.invalid("No visible window was found. Open the page you want help with, then activate Howdoey again.")
        }
        try Task.checkCancellation()
        // Tiny crops remove the filename's surrounding dialog context and make
        // OCR unreliable. Include a small neighborhood while retaining the exact
        // selected detail as the priority for structured control labels.
        let captureScope: CGRect
        if region != nil && (requested.width < 240 || requested.height < 80), let windowFrame = selectedBounds ?? ax.windowFrame {
            captureScope = requested.insetBy(dx:-90,dy:-60).intersection(windowFrame)
        } else { captureScope = requested }
        var capturedRegion = captureScope
        var image: NSImage?; var jpeg: Data?; var ocr = "Screen capture unavailable. Use Accessibility controls; enable Screen Recording to add OCR."
        if CGPreflightScreenCaptureAccess() {
            let secure = ax.secureFrames.contains { $0.intersects(captureScope) }
            if secure {
                ocr = "Image and OCR withheld because a secure text field is visible in the capture region."
            } else {
                let captured = try await capture(region: captureScope, pid: app.processIdentifier, windowID: selectedID)
                try Task.checkCancellation()
                let cg = captured.image
                capturedRegion = captured.region
                image = NSImage(cgImage: cg, size: capturedRegion.size)
                jpeg = NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.7])
                let lines = try await recognize(cg)
                try Task.checkCancellation()
                ocr = String(lines.map(\.text).joined(separator: "\n").prefix(10000))
                for line in lines.prefix(100) where ax.controls.count < 260 {
                    let r = line.rect
                    let frame = CGRect(x: capturedRegion.minX + r.minX * capturedRegion.width, y: capturedRegion.minY + (1 - r.maxY) * capturedRegion.height, width: r.width * capturedRegion.width, height: r.height * capturedRegion.height)
                    if !ax.controls.contains(where: { $0.label == line.text && $0.frame.intersects(frame) }) {
                        let id = (ax.controls.map(\.id).max() ?? 0) + 1
                        ax.controls.append(Control(id: id, role: "OCRText", label: line.text, value: "", frame: frame, actions: [], editable: false, enabled: true))
                    }
                }
            }
        }
        if UserDefaults.standard.bool(forKey: "captureDiagnostics") {
            let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Howdoey/CaptureDiagnostics")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if let jpeg { try? jpeg.write(to: folder.appendingPathComponent("last.jpg"), options: .atomic) }
            let details: [String:Any] = ["region": NSStringFromRect(capturedRegion), "windowID": selectedID ?? 0, "controls": ax.controls.count, "jpegBytes": jpeg?.count ?? 0, "secureFields": ax.secureFrames.count]
            if let data = try? JSONSerialization.data(withJSONObject: details) { try? data.write(to: folder.appendingPathComponent("last.json"),options: .atomic) }
        }
        return Observation(appName: app.localizedName ?? "Application", bundleID: app.bundleIdentifier ?? "", pid: app.processIdentifier, ax: ax, ocr: ocr, image: image, jpeg: jpeg, region: capturedRegion, capturedAt: Date(), windowID: selectedID, selectedDetail: region)
    }
    struct Capture { let image: CGImage; let region: CGRect }
    func capture(region: CGRect, pid: pid_t, windowID: CGWindowID? = nil) async throws -> Capture {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: windowID == nil)
        let config = SCStreamConfiguration()
        let filter: SCContentFilter
        let rect: CGRect
        let fullFrame: CGRect
        let windows = content.windows.filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.intersects(region) }
        let exactWindow = windowID.flatMap { id in windows.first { $0.windowID == id } }
        if windowID != nil && exactWindow == nil { throw AgentError.invalid("The selected window changed. Ask again to refresh it.") }
        if let window = exactWindow ?? windows.first {
            // Capture only the target window, even if another application is covering it.
            filter = SCContentFilter(desktopIndependentWindow: window)
            rect = region.intersection(window.frame)
            fullFrame = window.frame
            config.ignoreShadowsSingleWindow = true
        } else {
            guard let display = content.displays.max(by: { $0.frame.intersection(region).area < $1.frame.intersection(region).area }), display.frame.intersects(region) else { throw AgentError.invalid("The selected display is unavailable.") }
            let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            rect = region.intersection(display.frame)
            fullFrame = display.frame
        }
        // Capture the entire window before cropping. SCStream sourceRect uses
        // display logical coordinates and can return blank pixels when given a
        // window-relative rectangle. Keep pixel cropping in one known space.
        guard !rect.isEmpty else { throw AgentError.invalid("The selected area is outside the window. Select again.") }
        let scale: CGFloat = rect.width < fullFrame.width * 0.5 ? 2 : min(2, 2000 / max(fullFrame.width, fullFrame.height))
        config.width = max(1, Int(fullFrame.width * scale)); config.height = max(1, Int(fullFrame.height * scale))
        config.showsCursor = false
        if UserDefaults.standard.bool(forKey: "captureDiagnostics") {
            let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Howdoey/CaptureDiagnostics")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,attributes: [.posixPermissions: 0o700])
            let details: [String:Any] = ["fullFrame": NSStringFromRect(fullFrame),"filterContentRect": NSStringFromRect(filter.contentRect),"crop": NSStringFromRect(rect),"width":config.width,"height":config.height]
            if let data = try? JSONSerialization.data(withJSONObject:details) { try? data.write(to:folder.appendingPathComponent("capture.json"),options:.atomic) }
        }
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let sx = CGFloat(image.width) / fullFrame.width
        let sy = CGFloat(image.height) / fullFrame.height
        let pixels = CGRect(x: (rect.minX-fullFrame.minX)*sx, y: (rect.minY-fullFrame.minY)*sy,
                            width: rect.width*sx, height: rect.height*sy).integral
        guard let cropped = image.cropping(to: pixels) else { throw AgentError.invalid("Could not crop the selected area. Select again.") }
        return Capture(image: cropped, region: rect)
    }

    struct OCRLine: Sendable { let text: String; let rect: CGRect }
    private func recognize(_ image: CGImage) async throws -> [OCRLine] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { result in
                guard let text = result.topCandidates(1).first?.string else { return nil }
                return OCRLine(text: text, rect: result.boundingBox)
            }
        }.value
    }
}
private extension CGRect { var area: CGFloat { isNull ? 0 : width * height } }
