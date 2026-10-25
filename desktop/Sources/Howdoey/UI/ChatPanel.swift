// Floating chat panel: window controller plus SwiftUI content.
import AppKit
import SwiftUI
import HowdoeyCore

@MainActor final class ChatPanelController {
    private let panel: KeyablePanel
    private var hasBeenPlaced = false

    init(model: AppModel) {
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 680),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ChatPanelView(model: model))
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        if !panel.isVisible && !hasBeenPlaced { place() }
        panel.orderFrontRegardless()
        panel.makeKey()
    }
    func hide() { panel.orderOut(nil) }

    private func place() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        let height = min(680, area.height - 32)
        panel.setFrame(NSRect(x: area.maxX - 420 - 16, y: area.maxY - height - 16, width: 420, height: height), display: true)
        hasBeenPlaced = true
    }
}

struct ChatPanelView: View {
    @ObservedObject var model: AppModel
    @FocusState private var inputFocused: Bool
    @State private var hostIsTitled = false // a titled host window draws its own traffic lights and frame
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: hostIsTitled ? 0 : 20, style: .continuous) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            if model.showSettings {
                SettingsView(model: model)
            } else {
                contextCard
                conversation
                if let request = model.pendingApproval {
                    ApprovalView(model: model, request: request).padding(.horizontal, 14).padding(.bottom, 8)
                }
                if let error = model.errorMessage { errorBanner(error) }
                composer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.18)))
        .background(WindowChromeReader(isTitled: $hostIsTitled))
        .onAppear { inputFocused = true }
    }

    // MARK: Header
    private var header: some View {
        HStack(spacing: 8) {
            if hostIsTitled { Spacer().frame(width: 64) } // clear the window's close/minimize/zoom buttons
            BrandMark(size: 26)
            Text("Howdoey").font(.system(size: 20, weight: .bold, design: .rounded))
            Spacer()
            statusChip
            Button { model.clearConversation() } label: { Image(systemName: "square.and.pencil").font(.system(size: 17)) }
                .buttonStyle(.plain).help("New chat").accessibilityLabel("Clear chat")
            Button { model.showSettings.toggle() } label: { Image(systemName: "gearshape").font(.system(size: 17)) }
                .buttonStyle(.plain).help("Permissions and AI model").accessibilityLabel("Settings")
            Button { model.closePanel() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(.secondary) }
                .buttonStyle(.plain).help("Close").accessibilityLabel("Close")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var statusChip: some View {
        HStack(spacing: 5) {
            if model.isBusy && model.phase != .awaitingApproval && model.phase != .demonstrating { ProgressView().controlSize(.mini) }
            Text(model.phase.rawValue).font(.system(size: 12, weight: .medium)).lineLimit(1).frame(maxWidth: 112)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(chipColor.opacity(0.18), in: Capsule())
        .foregroundStyle(chipColor)
    }
    private var chipColor: Color {
        switch model.phase {
        case .failed: return .red
        case .complete: return .green
        case .stopped, .idle: return .secondary
        default: return .accentColor
        }
    }

    // MARK: Selection context
    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image = model.selectionImage {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button { model.clearSelection() } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 22)).symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .buttonStyle(.plain).padding(6).help("Clear selection").accessibilityLabel("Clear selection")
                        .disabled(model.isBusy)
                    }
                    .accessibilityLabel("Preview of your selection")
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.targetApplication.isEmpty ? "Current window" : model.targetApplication)
                        .font(.system(size: 15, weight: .semibold))
                    if model.selectionIsExplicit { Text("Selected area").font(.system(size: 13)).foregroundStyle(.secondary) }
                }
                Spacer()
            }
            HStack {
                Button { model.selectRegion() } label: { Label("Select an area", systemImage: "viewfinder") }
                    .buttonStyle(.borderedProminent)
                Button { model.selectWindow() } label: { Label("Select a window", systemImage: "macwindow") }
            }
            .controlSize(.large).disabled(model.isBusy)
        }
        .padding(14)
    }

    // MARK: Conversation
    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.messages) { MessageBubble(message: $0) }
                    if model.isBusy && model.phase != .awaitingApproval && model.phase != .demonstrating {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(model.phase.rawValue + "…").font(.system(size: 14)).foregroundStyle(.secondary) }
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 14)
            }
            .onChange(of: model.messages.count) { _, _ in DispatchQueue.main.async { proxy.scrollTo("end", anchor: .bottom) } }
        }
        .frame(maxHeight: .infinity)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Settings") { model.showSettings = true }.controlSize(.small)
            Button { model.errorMessage = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss")
        }
        .padding(10)
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 14).padding(.bottom, 6)
    }

    // MARK: Composer
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isBusy {
                Button(role: .destructive) { model.stop() } label: { Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("How can I help?", text: $model.draft, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 16)).lineLimit(1...4)
                    .padding(10).background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .focused($inputFocused)
                    .onSubmit { model.submit() }
                    .disabled(model.isBusy)
                Button { model.submit() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)) }
                    .buttonStyle(.plain).foregroundStyle(model.canSubmit ? Color.accentColor : Color.secondary)
                    .disabled(!model.canSubmit).accessibilityLabel("Send")
                    .help(model.canSubmit ? "Send" : "Type a question about your active window")
            }
        }
        .padding(14)
    }




}

struct MessageBubble: View {
    let message: ChatMessage

    private var text: AttributedString {
        (try? AttributedString(markdown: message.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.text)
    }

    var body: some View {
        switch message.role {
        case .user:
            Text(text).font(.system(size: 16)).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .assistant:
            Text(text).font(.system(size: 16)).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .system:
            Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
        }
    }
}

/// Reports whether the hosting window has a title bar, so the layout can avoid its controls.
struct WindowChromeReader: NSViewRepresentable {
    @Binding var isTitled: Bool
    final class Probe: NSView {
        var onChange: ((Bool) -> Void)?
        override func viewDidMoveToWindow() {
            let titled = window?.styleMask.contains(.titled) ?? false
            DispatchQueue.main.async { [onChange] in onChange?(titled) }
        }
    }
    func makeNSView(context: Context) -> Probe { let v = Probe(); v.onChange = { isTitled = $0 }; return v }
    func updateNSView(_ nsView: Probe, context: Context) { nsView.onChange = { isTitled = $0 } }
}
