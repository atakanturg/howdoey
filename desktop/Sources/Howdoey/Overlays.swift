// Codex-owned window lifecycle. Claude owns the pure SwiftUI selection content.
import AppKit
import SwiftUI
import HowdoeyCore

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
@MainActor final class OverlayController {
    private var selectionWindows: [NSPanel] = []
    private var guideWindows: [NSPanel] = []
    private var progressWindow: NSPanel?
    private var lastGuideRect: CGRect?
    private var keyMonitor: Any?
    private var cursorPushed = false
    private var generation = UUID()
    private var selectionTimeout: Task<Void, Never>?
    func dismissSelection() {
        selectionTimeout?.cancel(); selectionTimeout = nil
        generation = UUID()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }; keyMonitor = nil
        if cursorPushed { NSCursor.pop(); cursorPushed = false }
        selectionWindows.forEach { $0.orderOut(nil) }; selectionWindows = []
    }
    private func window(_ rect: CGRect, clickThrough: Bool = false) -> OverlayPanel {
        let panel = OverlayPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .screenSaver; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = clickThrough
        return panel
    }
    func select(kind: SelectionKind, completion: @escaping (CGRect?, pid_t?) -> Void) {
        dismissSelection()
        let token = generation
        for screen in NSScreen.screens {
            let panel = window(screen.frame)
            let finish: (CGRect?, pid_t?) -> Void = { [weak self] region, pid in
                guard let self, generation == token else { return }
                let owner = pid ?? region.flatMap { WindowHitTest.topWindow(at: CGPoint(x: $0.midX, y: $0.midY))?.pid }
                dismissSelection()
                completion(region, owner)
            }
            if kind == .element {
                let surface = ElementSurface(frame: CGRect(origin: .zero, size: screen.frame.size))
                surface.onClick = { local in
                    let cocoa = CGRect(x: screen.frame.minX + local.x - 2, y: screen.frame.minY + local.y - 2, width: 4, height: 4)
                    finish(quartzRect(cocoa), nil)
                }
                panel.contentView = surface
            } else {
                let content = QuietSelectionSurface(kind: kind, screenFrame: screen.frame, onFinish: finish)
                let hosting = NSHostingView(rootView: content)
                hosting.sizingOptions = []
                panel.contentView = hosting
            }
            panel.setFrame(screen.frame, display: false)
            panel.makeKeyAndOrderFront(nil)
            selectionWindows.append(panel)
        }
        selectionWindows.first(where: { $0.frame.contains(NSEvent.mouseLocation) })?.makeKey()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let activationShortcut = event.keyCode == 49 && event.modifierFlags.contains([.control, .option])
            if event.keyCode == 53 || activationShortcut {
                self?.dismissSelection(); completion(nil, nil); return nil
            }
            return event
        }
        NSCursor.crosshair.push(); cursorPushed = true
        selectionTimeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 90_000_000_000) } catch { return }
            guard let self, generation == token else { return }
            dismissSelection(); completion(nil, nil)
        }
    }
    func updateProgressControls(model: AppModel, phase: SessionPhase) {
        guard model.sessionMode == .show, [.observing,.thinking,.demonstrating,.verifying,.complete,.failed].contains(phase) else { progressWindow?.orderOut(nil); lastGuideRect = nil; return }
        let anchor = (model.demonstration?.rect ?? lastGuideRect).map { cocoaRect($0) }
        let visible = (NSScreen.screens.first { screen in anchor.map { screen.frame.intersects($0) } ?? false } ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let rect = GuideGeometry.sidePanel(in:visible,size:CGSize(width:344,height:270),avoiding:anchor)
        if progressWindow == nil {
            let panel = OverlayPanel(contentRect:rect,styleMask:[.borderless],backing:.buffered,defer:false)
            panel.isOpaque = false; panel.backgroundColor = .clear
            panel.level = .floating; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
            panel.title = "Howdoey — Next step"
            panel.hasShadow = true; panel.isMovableByWindowBackground = true
            panel.contentView = NativeGuideCard(frame: CGRect(origin: .zero,size: rect.size))
            progressWindow = panel
        }
        (progressWindow?.contentView as? NativeGuideCard)?.update(model: model, phase: phase)
        if progressWindow?.isKeyWindow != true { progressWindow?.setFrame(rect,display: true) }
        progressWindow?.orderFrontRegardless()
    }
    func showDemonstration(_ target: DemonstrationTarget?) {
        guard let target else {
            guideWindows.forEach { $0.orderOut(nil) }; guideWindows = []; return
        }
        lastGuideRect = target.rect
        guard NSScreen.screens.contains(where: { GuideGeometry.isCompactTarget(target.rect, in: quartzRect($0.frame)) }) else { return }
        let rect = cocoaRect(target.rect).insetBy(dx: -5, dy: -5)
        let marker: NSPanel
        if let existing = guideWindows.first { marker = existing }
        else {
            marker = window(rect, clickThrough: true)
            marker.contentView = TargetOutline(frame: CGRect(origin: .zero, size: rect.size))
            guideWindows = [marker]
        }
        // Only the outline moves. No simulated cursor, screen veil or floating caption.
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if marker.isVisible && !reduce {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                marker.animator().setFrame(rect, display: true)
            }
        } else {
            marker.setFrame(rect, display: false)
            marker.alphaValue = reduce ? 1 : 0
            marker.orderFrontRegardless()
            if !reduce {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15; marker.animator().alphaValue = 1
                }
            }
        }
    }

}
private final class ElementSurface: NSView {
    var onClick: ((CGPoint) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseUp(with event: NSEvent) { onClick?(convert(event.locationInWindow, from: nil)) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill()
        let text = "Click a control to select it · Esc to cancel"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18, weight: .medium), .foregroundColor: NSColor.labelColor]
        let size = (text as NSString).size(withAttributes: attributes)
        let pill = CGRect(x: bounds.midX - size.width / 2 - 22, y: bounds.maxY - 110, width: size.width + 44, height: 54)
        NSColor.windowBackgroundColor.setFill(); NSBezierPath(roundedRect: pill, xRadius: 27, yRadius: 27).fill()
        (text as NSString).draw(at: CGPoint(x: pill.minX + 22, y: pill.minY + 16), withAttributes: attributes)
    }
}
private final class TargetOutline: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 2, dy: 2)
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        path.fill()
        NSColor.white.withAlphaComponent(0.95).setStroke(); path.lineWidth = 6; path.stroke()
        NSColor.controlAccentColor.setStroke(); path.lineWidth = 3.5; path.stroke()
    }
}

@MainActor private final class NativeGuideCard: NSView, NSTextFieldDelegate {
    private weak var model: AppModel?
    private let heading = NSTextField(labelWithString:"Your next step")
    private let instruction = NSTextView()
    private let instructionScroll = NSScrollView()
    private let newChatButton = NSButton()
    private var conversationID: UUID?
    private let checkButton = NSButton(title:"Check progress",target:nil,action:nil)
    private let stopButton = NSButton(title:"Stop",target:nil,action:nil)
    private let input = NSTextField(string:"")
    private let sendButton = NSButton(title:"Send",target:nil,action:nil)
    override init(frame:NSRect) {
        super.init(frame:frame)
        let material = NSVisualEffectView(frame:bounds)
        material.autoresizingMask = [.width,.height]; material.material = .popover; material.state = .active
        material.wantsLayer = true; material.layer?.cornerRadius = 14; material.layer?.masksToBounds = true
        addSubview(material)
        heading.frame = CGRect(x:16,y:234,width:264,height:22)
        heading.font = .systemFont(ofSize:15,weight:.semibold); heading.lineBreakMode = .byTruncatingTail
        instructionScroll.frame = CGRect(x:16,y:103,width:312,height:122)
        instructionScroll.hasVerticalScroller = true; instructionScroll.autohidesScrollers = true
        instructionScroll.drawsBackground = false; instructionScroll.borderType = .noBorder
        instruction.frame = CGRect(x:0,y:0,width:296,height:122)
        instruction.font = .systemFont(ofSize:14); instruction.textColor = .labelColor
        instruction.isEditable = false; instruction.isSelectable = true; instruction.drawsBackground = false
        instruction.isVerticallyResizable = true; instruction.isHorizontallyResizable = false
        instruction.autoresizingMask = [.width]; instruction.textContainerInset = CGSize(width:0,height:3)
        instruction.maxSize = CGSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        instruction.textContainer?.containerSize = CGSize(width:296,height:CGFloat.greatestFiniteMagnitude)
        instruction.textContainer?.widthTracksTextView = true
        instructionScroll.documentView = instruction
        newChatButton.frame = CGRect(x:292,y:231,width:36,height:28)
        newChatButton.image = NSImage(systemSymbolName:"square.and.pencil",accessibilityDescription:"Clear chat")
        newChatButton.bezelStyle = .rounded; newChatButton.target = self; newChatButton.action = #selector(newChat)
        newChatButton.toolTip = "New chat"
        checkButton.frame = CGRect(x:12,y:65,width:192,height:30); checkButton.bezelStyle = .rounded
        checkButton.target = self; checkButton.action = #selector(check)
        checkButton.toolTip = "Optional: check now. Clicks in the guided app also trigger a check."
        stopButton.frame = CGRect(x:240,y:65,width:88,height:30); stopButton.bezelStyle = .rounded
        stopButton.target = self; stopButton.action = #selector(stop)
        input.frame = CGRect(x:16,y:18,width:250,height:34)
        input.placeholderString = "How can I help?"; input.font = .systemFont(ofSize:14)
        input.bezelStyle = .roundedBezel; input.delegate = self
        input.setAccessibilityLabel("Ask Howdoey")
        sendButton.frame = CGRect(x:275,y:17,width:57,height:36); sendButton.bezelStyle = .rounded
        sendButton.target = self; sendButton.action = #selector(sendQuestion); sendButton.isEnabled = false
        for view in [heading,instructionScroll,newChatButton,checkButton,stopButton,input,sendButton] as [NSView] { addSubview(view) }
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is unsupported") }
    func update(model:AppModel,phase:SessionPhase) {
        self.model = model
        if conversationID != model.conversationID {
            conversationID = model.conversationID; instruction.string = ""; input.stringValue = ""
        }
        switch phase {
        case .observing: heading.stringValue = "Looking…"
        case .thinking: heading.stringValue = "Thinking…"
        case .verifying: heading.stringValue = "Checking…"
        case .complete: heading.stringValue = "Good work!"
        case .failed: heading.stringValue = "Needs attention"
        default: heading.stringValue = model.demonstration?.label.isEmpty == false ? model.demonstration!.label : "Howdoey"
        }
        let loading = [.observing,.thinking,.verifying].contains(phase)
        let text = model.errorMessage ?? model.demonstration?.caption ?? model.messages.last(where: { $0.role == .assistant })?.text
        // Preserve the complete previous instruction while the next one loads.
        let next = loading ? (instruction.string.isEmpty ? "Reading your window…" : instruction.string) : (text ?? "How can I help?")
        if instruction.string != next {
            instruction.string = next
            if let container = instruction.textContainer, let layout = instruction.layoutManager {
                layout.ensureLayout(for:container)
                instruction.setFrameSize(CGSize(width:instruction.frame.width,height:max(122,ceil(layout.usedRect(for:container).height)+12)))
            }
            instruction.scrollRangeToVisible(NSRange(location:0,length:0))
        }
        checkButton.isEnabled = model.canCheckProgress
        sendButton.isEnabled = !input.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
    }
    func controlTextDidChange(_ notification:Notification) {
        sendButton.isEnabled = !input.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
    }
    func control(_ control:NSControl,textView:NSTextView,doCommandBy selector:Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { sendQuestion(); return true }
        return false
    }
    @objc private func sendQuestion() {
        let text = input.stringValue
        guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
        input.stringValue = ""; sendButton.isEnabled = false
        model?.submitGuideQuestion(text)
    }
    @objc private func newChat() { model?.clearConversation() }
    @objc private func check() { model?.checkProgress() }
    @objc private func stop() { model?.stop(); model?.showPanelHandler?() }
}

private struct QuietSelectionSurface: View {
    let kind: SelectionKind
    let screenFrame: CGRect
    let onFinish: (CGRect?, pid_t?) -> Void
    @State private var start: CGPoint?
    @State private var current: CGPoint?
    @State private var hovered: WindowTarget?
    private var origin: CGPoint { ScreenGeometry.quartzOrigin(of: screenFrame) }
    private func quartz(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + origin.x, y: p.y + origin.y) }
    private var selection: CGRect? {
        if kind == .window { return hovered?.rect.offsetBy(dx: -origin.x, dy: -origin.y) }
        guard let start, let current else { return nil }
        return CGRect(x: min(start.x,current.x), y: min(start.y,current.y), width: abs(start.x-current.x), height: abs(start.y-current.y))
    }
    var body: some View {
        ZStack(alignment: .top) {
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero,size: size)), with: .color(.blue.opacity(0.22)))
                if let rect = selection {
                    let path = Path(roundedRect: rect, cornerRadius: 5)
                    context.blendMode = .destinationOut
                    context.fill(path,with:.color(.white))
                    context.blendMode = .normal
                    context.stroke(path,with:.color(.white),lineWidth:6)
                    context.stroke(path,with:.color(.accentColor),lineWidth:3)
                    for point in [CGPoint(x:rect.minX,y:rect.minY),CGPoint(x:rect.maxX,y:rect.minY),CGPoint(x:rect.minX,y:rect.maxY),CGPoint(x:rect.maxX,y:rect.maxY)] {
                        context.fill(Path(ellipseIn:CGRect(x:point.x-4,y:point.y-4,width:8,height:8)),with:.color(.white))
                    }
                }
            }.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    if kind == .region { start = start ?? value.startLocation; current = value.location }
                }.onEnded { value in
                    if kind == .window, let target = WindowHitTest.topWindow(at: quartz(value.location)) {
                        onFinish(target.rect, target.pid)
                    } else if let rect = selection, rect.width >= 8, rect.height >= 8 {
                        onFinish(CGRect(origin: quartz(rect.origin), size: rect.size), nil)
                    } else if kind == .region {
                        let point = quartz(value.location)
                        onFinish(CGRect(x:point.x-2,y:point.y-2,width:4,height:4),nil)
                    }
                })
                .onContinuousHover { phase in
                    guard kind == .window else { return }
                    if case .active(let point) = phase { hovered = WindowHitTest.topWindow(at: quartz(point)) }
                    else { hovered = nil }
                }
            HStack(spacing: 18) {
                Label(kind == .window ? "Click the window you want help with" : "Drag around what you want help with", systemImage: "viewfinder")
                    .font(.system(size: 14, weight: .medium))
                Divider().frame(height: 20)
                Button { onFinish(nil,nil) } label: {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                }.buttonStyle(.plain).help("Cancel selection (Escape)")
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .padding(.top, 68)
        }.frame(width: screenFrame.width, height: screenFrame.height)
    }
}
