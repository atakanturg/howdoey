// Codex-owned functional test UI. Replaced by Claude's HowdoeyPanelView at integration.
import SwiftUI
import AppKit
import HowdoeyCore

struct BackendTestPanel: View {
    @ObservedObject var model: AppModel
    @FocusState private var inputFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "viewfinder").font(.system(size: 23, weight: .medium)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) { Text("Howdoey").font(.system(size: 21, weight: .semibold)); Text("A little help, right here.").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button { model.showSettings.toggle() } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).help("Permissions and AI settings")
            }.padding(.horizontal, 22).padding(.top, 32).padding(.bottom, 18)
            Divider()
            if model.showSettings { settings }
            else { session }
        }
        .background(.ultraThinMaterial)
        .frame(minWidth: 360, idealWidth: 420, minHeight: 480, idealHeight: 680)
        .onAppear { inputFocused = true }
    }
    private var session: some View {
        VStack(spacing: 14) {
            HStack {
                Menu { Button("Select an area", action: model.selectRegion); Button("Select a control", action: model.selectElement); Button("Use active window", action: model.selectWindow) } label: { Label("Select screen", systemImage: "viewfinder") }
                    .disabled(model.isBusy)
                Spacer()
                Text("⌃⌥ Space").font(.caption).foregroundStyle(.secondary)
                Button { model.clearConversation() } label: { Image(systemName: "arrow.counterclockwise") }.buttonStyle(.plain).help("Clear conversation")
            }
            if let image = model.selectionImage {
                HStack(spacing: 12) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 66, height: 48).clipShape(RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 3) { Text(model.targetApplication).font(.callout.bold()); Text("Selection attached").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button(action: model.clearSelection) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).disabled(model.isBusy)
                }.padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            } else { Text(model.selectionDescription).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if model.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("What would you like help with?").font(.title3.weight(.medium))
                                Text("Select a setting, a button, or an area of your screen. Then ask in your own words.").foregroundStyle(.secondary)
                                Text("Ask explains. Show Me points while you operate the computer.").font(.callout).foregroundStyle(.secondary)
                            }.padding(.vertical, 22)
                        }
                        ForEach(model.messages) { message in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(message.role == .user ? "YOU" : message.role == .assistant ? "HOWDOEY" : "STATUS").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                                Text(message.text).font(.system(size: 15)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(message.role == .user ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13)).id(message.id)
                        }
                        if let approval = model.pendingApproval {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(approval.title, systemImage: "hand.raised").font(.headline)
                                Text(approval.detail).font(.callout)
                                if let source = approval.sourcePath { Text("From: \(source)").font(.caption).textSelection(.enabled) }
                                if let dest = approval.destinationPath { Text("To: \(dest)").font(.caption).textSelection(.enabled) }
                                HStack { Button("Cancel", action: model.cancelApproval); Spacer(); Button("Approve this step", action: model.approve).buttonStyle(.borderedProminent) }
                            }.padding(14).background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                        }
                        if let error = model.errorMessage { Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                        Color.clear.frame(height: 1).id("end")
                    }
                }.onChange(of: model.messages.count) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            }
            HStack(spacing: 8) {
                if [.thinking, .observing, .verifying].contains(model.phase) { ProgressView().controlSize(.small) }
                Text(model.phase.rawValue).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.canCheckProgress { Button("Check my progress", action: model.checkProgress).controlSize(.small) }
                if model.isBusy { Button("Stop", role: .destructive, action: model.stop).buttonStyle(.bordered).controlSize(.small) }
            }
            VStack(spacing: 8) {
                HStack(alignment: .bottom) {
                    TextField("Ask about your selection…", text: $model.draft, axis: .vertical).lineLimit(1...4).textFieldStyle(.plain).focused($inputFocused).onSubmit { model.submit() }.disabled(model.isBusy)
                    Button(action: model.submit) { Image(systemName: "arrow.up.circle.fill").font(.system(size: 28)) }.buttonStyle(.plain).disabled(!model.canSubmit).help("Send question")
                }.padding(13).background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                Text(model.configuration.sendImages ? "Selected screenshots and readable context go to your chosen AI provider." : "Readable screen text goes to your chosen AI provider. Image sharing is off.").font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }.padding(18)
    }
    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Permissions & AI").font(.title2.weight(.semibold))
                Text("Howdoey reads only when you select something or run a task. During a task, it checks the target app’s current window after each step.").font(.callout).foregroundStyle(.secondary)
                permission("Accessibility", detail: "Read native controls and perform approved actions.", granted: model.permissions.accessibility, request: model.requestAccessibility, settings: model.openAccessibilitySettings)
                permission("Screen Recording", detail: "Capture your selection and recognize visible text.", granted: model.permissions.screenRecording, request: model.requestScreenRecording, settings: model.openScreenRecordingSettings)
                Text("After granting Screen Recording, quit and reopen Howdoey if capture remains unavailable.").font(.caption).foregroundStyle(.secondary)
                Divider()
                Picker("Provider", selection: $model.providerPreset) { ForEach(ProviderPreset.allCases) { Text($0.rawValue).tag($0) } }.onChange(of: model.providerPreset) { model.applyProviderPreset() }
                TextField("API base URL (ends in /v1)", text: $model.configuration.endpoint)
                SecureField("API key (not needed for local Ollama)", text: $model.apiKeyInput)
                HStack { TextField("Model ID", text: $model.configuration.model); Button("Load models", action: model.fetchModels).disabled(model.isCheckingProvider) }
                if !model.availableModels.isEmpty {
                    Picker("Available models", selection: $model.configuration.model) {
                        Text("Choose a model").tag("")
                        ForEach(model.availableModels, id: \.self) { Text($0).tag($0) }
                    }
                }
                Toggle("Send screenshots to this provider", isOn: $model.configuration.sendImages)
                Text("Off by default. Accessibility labels and recognized text are still shared. Screenshots can contain sensitive information; inspect your selection before sending. Use a vision model when enabled.").font(.caption).foregroundStyle(.secondary)
                HStack { Button("Test connection", action: model.testProvider).disabled(model.isCheckingProvider); if model.isCheckingProvider { ProgressView().controlSize(.small) }; Spacer(); Button("Save", action: model.saveSettings).buttonStyle(.borderedProminent) }
                Text(model.settingsStatus).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Divider()
                Text("Local test build • macOS 14+\nControl–Option–Space opens Howdoey.\nNo screen or conversation history is saved.").font(.caption).foregroundStyle(.secondary)
                HStack { Button("Quit Howdoey") { NSApp.terminate(nil) }; Spacer(); Button("Done") { model.saveSettings(); model.showSettings = false } }
            }.padding(20).textFieldStyle(.roundedBorder)
        }.disabled(model.isBusy)
    }
    private func permission(_ name: String, detail: String, granted: Bool, request: @escaping () -> Void, settings: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(name + (granted ? " · Allowed" : " · Needed"), systemImage: granted ? "checkmark.circle.fill" : "lock.shield").font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary)
            if !granted { HStack { Button("Allow \(name)", action: request); Button("Open Settings", action: settings) } }
        }
    }
}
