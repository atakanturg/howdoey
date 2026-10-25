import Foundation
let endpoint = "http://127.0.0.1:8767/v1"
let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Howdoey/ClaudeDemo")
guard FileManager.default.fileExists(atPath: root.appendingPathComponent("token").path) else { fatalError("Start run-claude-demo.sh first") }
let defaults = UserDefaults(suiteName: "com.howdoey.desktop")!
if defaults.data(forKey: "claudeDemoPreviousConfiguration") == nil, let previous = defaults.data(forKey: "providerConfiguration") { defaults.set(previous, forKey: "claudeDemoPreviousConfiguration") }
let config = try JSONSerialization.data(withJSONObject: ["endpoint": endpoint, "model": "claude-haiku-5-5", "sendImages": true])
defaults.set(config, forKey: "providerConfiguration")
print("Configured Howdoey for the local Claude Code demo. Screenshots enabled. Restart Howdoey to apply.")
