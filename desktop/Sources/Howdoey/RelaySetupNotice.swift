// Backend integration notice. Keeps Claude's UI files untouched.
import SwiftUI
import AppKit

struct RelaySetupNotice: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if model.showSettings {
            VStack(alignment: .leading, spacing: 6) {
                if !model.permissions.accessibility || !model.permissions.screenRecording {
                    Text("macOS currently denies access to this build. An enabled Settings entry can still refer to an older signature. Authorize the current app after signing is finalized; indicators refresh automatically.").font(.caption).foregroundStyle(.orange)
                    Button("Refresh access status", action: model.refreshPermissions).controlSize(.small)
                }
                if model.providerPreset == .shared {
                    Text("Use your Howdoey access token in the API key field. The developer's Groq key stays on the server.").font(.caption)
                    Text("This service forwards questions and screen context to Groq, even when the address is localhost.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("For developer-funded access, choose Howdoey shared AI. Each user gets an access token instead of your Groq key.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Developer Groq setup…") { model.openSharedSetup() }.controlSize(.small)
                    Text("Local relay: port 8766").font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
        }
    }
}
@MainActor extension AppModel {
    func openSharedSetup() {
        let url = URL(string: "http://127.0.0.1:8766/health")!
        Task {
            do {
                var request = URLRequest(url: url); request.timeoutInterval = 3
                let (_, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.cannotConnectToHost) }
                NSWorkspace.shared.open(URL(string: "http://127.0.0.1:8766/admin")!)
            } catch {
                settingsStatus = "Start the developer relay first: desktop/scripts/run-relay.sh. Then open Developer Groq setup. The key is entered on that local page, never in chat or the distributed app."
            }
        }
    }
}
