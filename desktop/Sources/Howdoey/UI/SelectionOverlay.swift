// Lens-style selection presentation. Rendering only: the backend captures after these windows are gone.
import AppKit
import SwiftUI

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class SelectionOverlayController {
    private var windows: [KeyablePanel] = []
    private var keyMonitor: Any?
    private var cursorPushed = false
    private(set) var isActive = false
    /// region is global Quartz points (nil for a whole window); the app owns the selected content.
    var onResult: ((CGRect?, NSRunningApplication) -> Void)?
    var onCancel: (() -> Void)?
    var onFailure: ((String) -> Void)?

    func begin(kind: SelectionKind) {
        end()
        isActive = true
        for screen in NSScreen.screens {
            let panel = KeyablePanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.setFrame(screen.frame, display: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.sharingType = .none // extra defence: never appear in captures
            panel.isReleasedWhenClosed = false
            let view = SelectionOverlayView(kind: kind, screenFrame: screen.frame,
                                            onFinish: { [weak self] region, pid in self?.finish(region: region, pid: pid) },
                                            onCancel: { [weak self] in self?.cancel() })
            panel.contentView = NSHostingView(rootView: view)
            panel.orderFrontRegardless()
            windows.append(panel)
        }
        windows.first(where: { $0.frame.contains(NSEvent.mouseLocation) })?.makeKey()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancel(); return nil } // Escape
            return event
        }
        NSCursor.crosshair.push(); cursorPushed = true
    }

    func end() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if cursorPushed { NSCursor.pop(); cursorPushed = false }
        windows.forEach { $0.orderOut(nil) }
        windows = []
        isActive = false
    }

    private func cancel() { guard isActive else { return }; end(); onCancel?() }

    private func finish(region: CGRect?, pid: pid_t?) {
        guard isActive else { return }
        end()
        Task { @MainActor in
            // Let the compositor drop the overlay before the backend captures the screen.
            try? await Task.sleep(nanoseconds: 200_000_000)
            var owner = pid
            if owner == nil, let region {
                owner = WindowHitTest.topWindow(at: CGPoint(x: region.midX, y: region.midY))?.pid
            }
            if owner == nil, let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                owner = front.processIdentifier
            }
            guard let owner, let app = NSRunningApplication(processIdentifier: owner) else {
                onFailure?("I couldn't tell which app that area belongs to. Try selecting it again.")
                return
            }
            onResult?(region, app)
        }
    }
}

struct SelectionOverlayView: View {
    let kind: SelectionKind
    let screenFrame: CGRect // Cocoa points
    let onFinish: (CGRect?, pid_t?) -> Void
    let onCancel: () -> Void

    @State private var start: CGPoint?
    @State private var current: CGPoint?
    @State private var hovered: WindowTarget?
    @State private var showHelp = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var origin: CGPoint { ScreenGeometry.quartzOrigin(of: screenFrame) }
    private func toQuartz(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + origin.x, y: p.y + origin.y) }
    private func toLocal(_ r: CGRect) -> CGRect { r.offsetBy(dx: -origin.x, dy: -origin.y) }

    private var dragRect: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(start.x - current.x), height: abs(start.y - current.y))
    }
    private var highlight: CGRect? {
        kind == .window ? hovered.map { toLocal($0.rect) } : dragRect
    }

    var body: some View {
        ZStack(alignment: .top) {
            Canvas { context, size in
                var path = Path(CGRect(origin: .zero, size: size))
                if let highlight { path.addRoundedRect(in: highlight, cornerSize: CGSize(width: 6, height: 6)) }
                context.fill(path, with: .color(.black.opacity(0.38)), style: FillStyle(eoFill: true))
                if let highlight {
                    context.stroke(Path(roundedRect: highlight, cornerRadius: 6), with: .color(.accentColor), lineWidth: 3)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    if kind == .region { start = start ?? value.startLocation; current = value.location }
                }
                .onEnded { value in finishDrag(at: value.location) })
            .onContinuousHover { phase in
                guard kind == .window else { return }
                if case .active(let point) = phase { hovered = WindowHitTest.topWindow(at: toQuartz(point)) } else { hovered = nil }
            }
            .accessibilityHidden(true)

            if let rect = dragRect, rect.width > 30, rect.height > 20 {
                Text("\(Int(rect.width)) × \(Int(rect.height))")
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.thinMaterial, in: Capsule())
                    .position(x: rect.midX, y: min(rect.maxY + 18, screenFrame.height - 16))
                    .allowsHitTesting(false)
            }

            HStack(spacing: 10) {
                Text(kind == .window ? "Click the window you want help with." : "Drag around something you want help with.")
                    .font(.system(size: 17, weight: .semibold))
                Text("Esc to cancel").font(.system(size: 14)).foregroundStyle(.secondary)
                Button { showHelp.toggle() } label: { Image(systemName: "questionmark.circle.fill").font(.system(size: 20)) }
                    .buttonStyle(.plain)
                    .help("Howdoey only looks at the part you select. Nothing is sent until you ask a question.")
                    .accessibilityLabel("Help")
                    .popover(isPresented: $showHelp) {
                        Text("Draw a box around a setting, button, or message. Howdoey only looks at that part of your screen, and nothing is sent anywhere until you ask a question.")
                            .font(.system(size: 15)).padding(14).frame(width: 280)
                    }
            }
            .padding(.horizontal, 18).padding(.vertical, 11)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
            .padding(.top, 54)
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: highlight)
    }

    private func finishDrag(at point: CGPoint) {
        switch kind {
        case .region:
            defer { start = nil; current = nil }
            guard let rect = dragRect, rect.width >= 12, rect.height >= 12 else { return }
            onFinish(CGRect(origin: toQuartz(rect.origin), size: rect.size), nil)
        case .window:
            guard let target = WindowHitTest.topWindow(at: toQuartz(point)) else { return }
            onFinish(nil, target.pid)
        case .element:
            onCancel()
        }
    }
}
