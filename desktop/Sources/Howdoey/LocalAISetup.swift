import AppKit
import CryptoKit
import HowdoeyCore

/// Downloads are only started by the user's Download local AI button.
/// The developer's provider credentials are never part of this installation.
@MainActor final class LocalAISetup {
    static let shared = LocalAISetup()
    static let model = "qwen3.5:2b"
    private let version = "v0.40.11"
    private let runtimeSHA256 = "aea7d3f2e32371b7644a6e2ec8d4f26820a0e3965918cce8a46cef3e947f6291"
    private let base = URL(string:"http://127.0.0.1:11434")!
    private var server: Process?
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 90; config.timeoutIntervalForResource = 5400
        return URLSession(configuration:config)
    }()
    private var root: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Howdoey/LocalAI") }
    private var installedCLI: URL? {
        let runtime = root.appendingPathComponent("Runtime/\(version)")
        var candidates = [URL(fileURLWithPath:"/Applications/Ollama.app/Contents/Resources/ollama"),
                          FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Ollama.app/Contents/Resources/ollama"),
                          URL(fileURLWithPath:"/usr/local/bin/ollama"), URL(fileURLWithPath:"/opt/homebrew/bin/ollama")]
        if let relative = try? String(contentsOf:runtime.appendingPathComponent("cli-path.txt"),encoding:.utf8) {
            let local = runtime.appendingPathComponent(relative).standardizedFileURL
            if local.path.hasPrefix(runtime.path+"/") { candidates.insert(local,at:0) }
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath:$0.path) }
    }
    private func isRunning() async -> Bool {
        var request = URLRequest(url:base.appendingPathComponent("api/version")); request.timeoutInterval = 2
        guard let (data,response) = try? await session.data(for:request), (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with:data) as? [String:Any], json["version"] is String else { return false }
        return true
    }
    func startInstalledService() async throws {
        if await isRunning() { return }
        guard let cli = installedCLI else { throw AgentError.invalid("Download local AI in Settings first.") }
        let process = Process(); process.executableURL = cli; process.arguments = ["serve"]
        var environment = ProcessInfo.processInfo.environment
        environment["OLLAMA_HOST"] = "127.0.0.1:11434"; environment["OLLAMA_NO_CLOUD"] = "true"
        environment["OLLAMA_CONTEXT_LENGTH"] = "8192"; environment["OLLAMA_DEBUG_LOG_REQUESTS"] = "false"
        process.environment = environment; process.currentDirectoryURL = cli.deletingLastPathComponent()
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); server = process
        for _ in 0..<60 {
            try Task.checkCancellation()
            if await isRunning() { return }
            if !process.isRunning { break }
            try await Task.sleep(nanoseconds:250_000_000)
        }
        throw AgentError.invalid("The local AI service did not start. Check that your Mac supports the downloaded Ollama runtime.")
    }
    private func installRuntime(status:(String)->Void) async throws {
        #if !arch(arm64)
        throw AgentError.invalid("This local AI download currently supports Apple silicon Macs only.")
        #else
        let fm = FileManager.default
        try fm.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let runtime = root.appendingPathComponent("Runtime/\(version)")
        let staging = root.appendingPathComponent("download-\(UUID().uuidString)")
        try fm.createDirectory(at:staging,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        defer { try? fm.removeItem(at:staging) }
        status("Downloading Ollama runtime (about 180 MB)…")
        let url = URL(string:"https://github.com/ollama/ollama/releases/download/\(version)/ollama-darwin.tgz")!
        let (temporary,response) = try await session.download(from:url)
        defer { try? fm.removeItem(at:temporary) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AgentError.invalid("The local runtime download failed. Try again.") }
        try Task.checkCancellation()
        status("Verifying the runtime download…")
        let expected = runtimeSHA256
        let valid = try await Task.detached(priority:.userInitiated) {
            let data = try Data(contentsOf:temporary,options:.mappedIfSafe)
            return SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() == expected
        }.value
        guard valid else { throw AgentError.invalid("The runtime checksum did not match. Nothing was installed.") }
        status("Installing the local runtime…")
        try await Task.detached(priority:.userInitiated) {
            let tar = Process(); tar.executableURL = URL(fileURLWithPath:"/usr/bin/tar")
            tar.arguments = ["-xzf",temporary.path,"-C",staging.path]
            tar.standardOutput = FileHandle.nullDevice; tar.standardError = FileHandle.nullDevice
            try tar.run(); tar.waitUntilExit()
            guard tar.terminationStatus == 0 else { throw AgentError.invalid("Could not unpack the local runtime.") }
        }.value
        try Task.checkCancellation()
        let enumerator = fm.enumerator(at:staging,includingPropertiesForKeys:[.isRegularFileKey])
        var binary: URL?
        while let file = enumerator?.nextObject() as? URL {
            if file.lastPathComponent == "ollama", (try? file.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile) == true, fm.isExecutableFile(atPath:file.path) { binary = file; break }
        }
        guard let binary else { throw AgentError.invalid("The runtime archive did not contain Ollama.") }
        let relative = String(binary.path.dropFirst(staging.path.count+1))
        try relative.write(to:staging.appendingPathComponent("cli-path.txt"),atomically:true,encoding:.utf8)
        try fm.createDirectory(at:runtime.deletingLastPathComponent(),withIntermediateDirectories:true)
        if fm.fileExists(atPath:runtime.path) { try fm.removeItem(at:runtime) }
        try fm.moveItem(at:staging,to:runtime)
        #endif
    }
    func install(status:(String)->Void) async throws {
        if !(await isRunning()), installedCLI == nil { try await installRuntime(status:status) }
        status("Starting local AI…")
        try await startInstalledService()
        status("Downloading Qwen3.5 2B. This may take several minutes…")
        var request = URLRequest(url:base.appendingPathComponent("api/pull")); request.httpMethod = "POST"
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject:["model":Self.model,"stream":true])
        let (bytes,response) = try await session.bytes(for:request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AgentError.invalid("The model download could not start. Try again.") }
        var finished = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.utf8.count < 100_000, let data = line.data(using:.utf8), let part = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { continue }
            if let error = part["error"] as? String { throw AgentError.invalid("Model download: \(String(error.prefix(300)))") }
            if let complete = part["completed"] as? Int64, let total = part["total"] as? Int64, total > 0 {
                status("Downloading model: \(ByteCountFormatter.string(fromByteCount:complete,countStyle:.file)) of \(ByteCountFormatter.string(fromByteCount:total,countStyle:.file))")
            } else if let message = part["status"] as? String {
                status(String(message.prefix(120))); finished = message == "success"
            }
        }
        guard finished else { throw AgentError.invalid("The model download was interrupted. Choose Download local AI to resume.") }
        status("Local AI is ready.")
    }
}

@MainActor extension AppModel {
    func downloadLocalAI() {
        guard !isSettingUpLocalAI else { return }
        isSettingUpLocalAI = true; localAIStatus = "Preparing local AI…"
        localAISetupTask = Task {
            defer { isSettingUpLocalAI = false; localAISetupTask = nil }
            do {
                try await LocalAISetup.shared.install { [weak self] message in self?.localAIStatus = message }
                try Task.checkCancellation()
                configuration = ProviderConfiguration(endpoint:"http://127.0.0.1:11434/v1",model:LocalAISetup.model,sendImages:true)
                providerPreset = .ollama; apiKeyInput = ""; availableModels = [LocalAISetup.model]
                saveSettings()
                localAIStatus = "Local AI is ready. You can close Settings and ask Howdoey."
            } catch is CancellationError { localAIStatus = "Download stopped. Choose Download local AI to resume." }
            catch { localAIStatus = error.localizedDescription }
        }
    }
    func cancelLocalAISetup() { localAISetupTask?.cancel() }
}
