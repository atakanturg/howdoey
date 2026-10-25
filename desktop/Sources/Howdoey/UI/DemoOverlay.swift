// Show Me presentation: click-through pointer, ring and caption, plus a small controls panel.
// Nothing here advances a step. The backend decides when a step is verified.
import AppKit
import SwiftUI

@MainActor final class DemoOverlayController {
    private var overlay: NSPanel?
    private var controls: KeyablePanel?
    private let model: AppModel

    init(model: AppModel) { self.model = model }

    func showOverlay() {
        let frame = ScreenGeometry.unionFrame
        if let overlay { overlay.setFrame(frame, display: true); overlay.orderFrontRegardless(); return }
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.setFrame(frame, display: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true // never block the app underneath
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: DemoOverlayView(model: model, unionFrame: frame))
        panel.orderFrontRegardless()
        overlay = panel
    }

    func hideOverlay() { overlay?.orderOut(nil); overlay = nil }

    func showControls(near target: CGRect?) {
        if controls == nil {
            let panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 150), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView: DemoControlsView(model: model))
            panel.contentView = hosting
            let size = hosting.fittingSize
            panel.setContentSize(NSSize(width: 440, height: max(size.height, 120)))
            controls = panel
        }
        // Keep the controls on the display the user is looking at: the target's, else the main one.
        if let controls, !controls.isVisible {
            let quartzCenter = target.map { CGPoint(x: $0.midX, y: $0.midY) }
            let screen = quartzCenter.flatMap { c in
                NSScreen.screens.first { s in
                    let o = ScreenGeometry.quartzOrigin(of: s.frame)
                    return CGRect(origin: o, size: s.frame.size).contains(c)
                }
            } ?? NSScreen.main
            if let area = screen?.visibleFrame {
                controls.setFrameOrigin(NSPoint(x: area.midX - 220, y: area.minY + 28))
            }
        }
        controls?.orderFrontRegardless()
    }
    func hideControls() { controls?.orderOut(nil) }
}

struct DemoOverlayView: View {
    @ObservedObject var model: AppModel
    let unionFrame: CGRect
    @State private var arrived = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var origin: CGPoint { ScreenGeometry.quartzOrigin(of: unionFrame) }

    var body: some View {
        GeometryReader { geo in
            if let target = model.demonstration {
                let rect = target.rect.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -6, dy: -6)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 4)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.12)))
                        .shadow(color: Color.accentColor.opacity(0.6), radius: pulse ? 14 : 4)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    caption(target.caption.shortStepCaption, rect: rect, in: geo.size)

                    // Pseudo-cursor: purely visual, the real pointer is never moved.
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white, .black)
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                        .position(x: arrived ? rect.midX + 10 : rect.midX + 160,
                                  y: arrived ? rect.midY + 14 : rect.midY + 130)
                        .allowsHitTesting(false)
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.75), value: rect)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.75), value: arrived)
                .onAppear {
                    arrived = true
                    if !reduceMotion { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true } }
                }
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func caption(_ text: String, rect: CGRect, in size: CGSize) -> some View {
        let below = rect.maxY + 70 < size.height
        Text(text)
            .font(.system(size: 18, weight: .semibold))
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
            .position(x: min(max(rect.midX, 200), size.width - 200),
                      y: below ? rect.maxY + 42 : rect.minY - 42)
    }
}

struct DemoControlsView: View {
    @ObservedObject var model: AppModel

    private var lastNote: String? { model.messages.last(where: { $0.role == .system })?.text }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if model.phase == .verifying { ProgressView().controlSize(.small) }
                else { Image(systemName: "hand.point.up.left.fill").foregroundStyle(Color.accentColor) }
                Text(model.demonstration?.caption.shortStepCaption ?? model.phase.rawValue)
                    .font(.system(size: 17, weight: .semibold)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            if model.phase == .verifying {
                Text("Checking what changed on your screen…").font(.system(size: 14)).foregroundStyle(.secondary)
            } else if model.phase == .demonstrating {
                Text("Do this step yourself. I'll check it when something changes, or tap Check my progress.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }
            if let note = lastNote { Text(note).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(3) }
            HStack {
                Button("Check my progress") { model.checkProgress() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!model.canCheckProgress)
                Spacer()
                Button("Stop", role: .destructive) { model.stop() }.controlSize(.large)
            }
        }
        .padding(16)
        .frame(width: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension String {
    /// The backend may send a whole explanation as the caption; on screen show only the first sentence.
    var shortStepCaption: String {
        let text = trimmingCharacters(in: .whitespacesAndNewlines)
        let first = text.range(of: #"[.!?](\s|$)"#, options: .regularExpression).map { String(text[..<$0.upperBound]) } ?? text
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 140 ? String(trimmed.prefix(137)) + "…" : trimmed
    }
}
