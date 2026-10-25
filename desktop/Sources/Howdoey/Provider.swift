import Foundation
import Security
import HowdoeyCore

struct ProviderClient {
    private static let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
    private func request(configuration: ProviderConfiguration, key: String, route: String) throws -> URLRequest {
        let base = try Policy.endpoint(configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines))
        var request = URLRequest(url: base.appendingPathComponent(route))
        request.timeoutInterval = 90
        var authorization = key
        if configuration.endpoint == "http://127.0.0.1:8767/v1" {
            let tokenURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Howdoey/ClaudeDemo/token")
            guard let token = try? String(contentsOf: tokenURL, encoding: .utf8), !token.isEmpty else {
                throw AgentError.invalid("Start the Claude Code demo bridge in Terminal first.")
            }
            authorization = token.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !authorization.isEmpty { request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AgentError.invalid("The provider returned no HTTP response.") }
        guard (200...299).contains(http.statusCode) else {
            // Never display response bodies: some servers echo authorization or captured text.
            let message: String
            switch http.statusCode {
            case 300..<400: message = "The provider tried to redirect the request. Use its direct API address."
            case 401, 403: message = "The AI service rejected your access token or key. Check AI Settings."
            case 429: message = "The AI service is temporarily at its usage limit. Wait a moment and try again."
            case 502: message = "The AI service returned no usable answer (HTTP 502). Try again or choose a different available model in AI Settings."
            case 503: message = "The AI service is not ready. Check the developer relay setup."
            default: message = "The AI service could not complete this request (HTTP \(http.statusCode)). Try a smaller selection or check AI Settings."
            }
            throw AgentError.invalid(message)
        }
        guard data.count < 8_000_000 else { throw AgentError.invalid("The provider response exceeded the size limit.") }
        return data
    }
    func models(configuration: ProviderConfiguration, key: String) async throws -> [String] {
        let data = try await perform(request(configuration: configuration, key: key, route: "models"))
        struct Models: Decodable { struct Model: Decodable { let id: String }; let data: [Model] }
        return try JSONDecoder().decode(Models.self, from: data).data.map(\.id).sorted()
    }
    func complete(configuration: ProviderConfiguration, key: String, system: String, user: String, jpeg: Data? = nil, jsonDecision: Bool = false) async throws -> String {
        guard !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AgentError.invalid("Choose a model in AI Settings first. Use Load models to see what your provider offers.") }
        var request = try request(configuration: configuration, key: key, route: "chat/completions")
        request.httpMethod = "POST"
        var content: Any = user
        if let jpeg, configuration.sendImages {
            content = [["type": "text", "text": user], ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]]] as [[String: Any]]
        }
        var payload: [String: Any] = [
            "model": configuration.model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": content]],
            "temperature": 0.2, "max_tokens": 1800, "stream": false
        ]
        let endpoint = try Policy.endpoint(configuration.endpoint)
        let localOllama = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(endpoint.host ?? "") && endpoint.port == 11434
        if localOllama {
            // Local Qwen's hidden thinking can consume the entire answer budget.
            if configuration.model.hasPrefix("qwen3") { payload["reasoning_effort"] = "none" }
            if jsonDecision { payload["response_format"] = ["type": "json_object"] }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let data = try await perform(request)
        struct Reply: Decodable { struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }; let choices: [Choice] }
        guard let text = try JSONDecoder().decode(Reply.self, from: data).choices.first?.message.content, !text.isEmpty else { throw AgentError.invalid("The provider returned no answer. This model may not support chat or image input.") }
        return text
    }
}
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
enum KeyStore {
    static let service = "com.howdoey.desktop.provider"
    static func read(account: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func write(_ key: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let status: OSStatus
        if key.isEmpty {
            status = SecItemDelete(query as CFDictionary)
        } else {
            let data = Data(key.utf8)
            let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if update == errSecItemNotFound {
                var insertion = query
                insertion[kSecValueData as String] = data
                insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                status = SecItemAdd(insertion as CFDictionary, nil)
            } else { status = update }
        }
        guard status == errSecSuccess || (key.isEmpty && status == errSecItemNotFound) else { throw AgentError.invalid("Keychain could not save the API key (\(status)).") }
    }
}
