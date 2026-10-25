// Permissions and model settings. The API key is passed to the backend's field and never stored here.
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    private var host: String { URL(string: model.configuration.endpoint)?.host ?? "the address above" }
    private var isLocal: Bool { ["localhost", "127.0.0.1", "::1"].contains(host) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                permissions
                localAI
                provider
                privacy
                HStack {
                    Button("Save") { model.saveSettings() }.buttonStyle(.borderedProminent).controlSize(.large)
                    Button("Test connection") { model.testProvider() }.controlSize(.large).disabled(model.isCheckingProvider)
                    if model.isCheckingProvider { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Done") { model.showSettings = false }.controlSize(.large)
                }
                if !model.settingsStatus.isEmpty {
                    Text(model.settingsStatus).font(.system(size: 14)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
        }
        .onAppear { model.refreshPermissions() }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Permissions").font(.system(size: 18, weight: .bold))
            permissionRow(title: "Screen Recording", granted: model.permissions.screenRecording,
                          why: "Lets Howdoey see your active window or the area you select. macOS may ask you to reopen Howdoey afterwards.",
                          request: model.requestScreenRecording, open: model.openScreenRecordingSettings)
            permissionRow(title: "Accessibility", granted: model.permissions.accessibility,
                          why: "Lets Howdoey read buttons and settings by name and point to the steps you can follow.",
                          request: model.requestAccessibility, open: model.openAccessibilitySettings)
        }
    }

    private func permissionRow(title: String, granted: Bool, why: String, request: @escaping () -> Void, open: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(granted ? .green : .orange)
                Text(title).font(.system(size: 16, weight: .semibold))
                Spacer()
                Text(granted ? "On" : "Off").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
            }
            Text(why).font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !granted {
                HStack {
                    Button("Ask macOS", action: request)
                    Button("Open System Settings", action: open)
                }.controlSize(.regular)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var localAI: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("Local AI").font(.system(size:18,weight:.bold))
            Text("Qwen3.5 2B runs on your Mac. First launch automatically downloads and configures Ollama and this model (about 3 GB). You can cancel or retry here. Apple silicon required; allow 8 GB of free disk space. Model weights: Apache 2.0. Runtime: MIT.")
                .font(.system(size:14)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            HStack {
                Button("Download local AI") { model.downloadLocalAI() }.disabled(model.isSettingUpLocalAI).buttonStyle(.borderedProminent)
                if model.isSettingUpLocalAI { ProgressView().controlSize(.small); Button("Cancel") { model.cancelLocalAISetup() } }
            }
            if !model.localAIStatus.isEmpty { Text(model.localAIStatus).font(.system(size:14)).fixedSize(horizontal:false,vertical:true) }
        }
    }

    private var provider: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI model").font(.system(size: 18, weight: .bold))
            Picker("Provider", selection: $model.providerPreset) {
                ForEach(ProviderPreset.allCases) { Text($0.rawValue).tag($0) }
            }
            .onChange(of: model.providerPreset) { _, _ in model.applyProviderPreset() }
            labeled("Address") { TextField("https://…", text: $model.configuration.endpoint).textFieldStyle(.roundedBorder) }
            labeled("Model") {
                HStack {
                    if model.availableModels.isEmpty {
                        TextField("Model name", text: $model.configuration.model).textFieldStyle(.roundedBorder)
                    } else {
                        Picker("", selection: $model.configuration.model) {
                            if !model.availableModels.contains(model.configuration.model) { Text(model.configuration.model.isEmpty ? "Choose…" : model.configuration.model).tag(model.configuration.model) }
                            ForEach(model.availableModels, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden()
                    }
                    Button("Find models") { model.fetchModels() }
                }
            }
            labeled(model.providerPreset == .shared ? "Howdoey access token" : "API key") {
                SecureField(model.providerPreset == .shared ? "Paste your Howdoey access token" : (isLocal ? "Not needed for a model on this Mac" : "Paste your key"), text: $model.apiKeyInput)
                    .textFieldStyle(.roundedBorder)
            }
            Text("Your key is saved in your Mac's Keychain when you tap Save.").font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What gets sent").font(.system(size: 18, weight: .bold))
            Label(model.providerPreset == .claudeDemo ? "Forwarded through Claude Code to Anthropic." : model.providerPreset == .shared ? "Forwarded through the Howdoey relay to Groq." : (isLocal ? "Sent to your local service (\(host))." : "Sent over the internet to \(host)."),
                  systemImage: isLocal ? "lock.fill" : "network")
                .font(.system(size: 15, weight: .semibold))
            Text("Your question and the text Howdoey reads from your active window or selected area are sent to the model you chose.")
                .font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Also send a picture of the selected area", isOn: $model.configuration.sendImages)
                .font(.system(size: 15))
            Text(model.configuration.sendImages ? (model.providerPreset == .claudeDemo ? "Pictures are forwarded to Anthropic through Claude Code." : "Pictures go to \(host) along with your question.") : "No pictures are sent. Only text read from the screen.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    private func labeled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }
}
