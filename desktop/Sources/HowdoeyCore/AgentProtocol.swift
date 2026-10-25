import Foundation

public enum Mode: String, CaseIterable, Codable { case ask = "Ask", show = "Show Me" }
public enum ActionKind: String, Codable { case press, setValue, openApplication, moveSelectedFile, wait }
public struct AgentAction: Codable, Equatable {
    public let kind: ActionKind
    public let target: Int?
    public let targetLabel: String?
    public let value: String?
    public let bundleID: String?
    public let folderName: String?
    public init(kind: ActionKind, target: Int? = nil, value: String? = nil, bundleID: String? = nil, folderName: String? = nil, targetLabel: String? = nil) {
        self.kind = kind; self.target = target; self.targetLabel = targetLabel; self.value = value; self.bundleID = bundleID; self.folderName = folderName
    }
}
public struct Decision: Codable {
    public let message: String
    public let done: Bool
    public let verifiedPrevious: Bool?
    public let action: AgentAction?
    public let progress: ProgressExpectation?
    public static func parse(_ content: String) throws -> Decision {
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.components(separatedBy: "\n").dropFirst().dropLast().joined(separator: "\n")
        }
        guard let data = text.data(using: .utf8) else { throw AgentError.invalid("The model returned unreadable text.") }
        let decision = try JSONDecoder().decode(Decision.self, from: data)
        guard !decision.message.isEmpty, decision.message.count <= 12000 else { throw AgentError.invalid("The model returned an invalid explanation.") }
        guard !(decision.done && decision.action != nil) else { throw AgentError.invalid("The model requested an action and completion together.") }
        return decision
    }
}
public enum AgentError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let message): return message } }
}
public enum Policy {
    public static let maximumFailures = 3
    public static func validate(_ action: AgentAction, mode: Mode, validTargets: Set<Int>) throws {
        guard mode != .ask else { throw AgentError.invalid("Ask mode cannot control the computer.") }
        switch action.kind {
        case .press, .setValue:
            guard let target = action.target, validTargets.contains(target) else { throw AgentError.invalid("The control is no longer available. Observe again.") }
            if action.kind == .setValue {
                guard let value = action.value, value.count <= 2000 else { throw AgentError.invalid("Typing is limited to 2,000 characters per step.") }
            }
        case .openApplication:
            guard let id = action.bundleID, ["com.apple.finder", "com.apple.systempreferences", "com.apple.Safari"].contains(id) else {
                throw AgentError.invalid("This build can open Finder, System Settings, or Safari. Open other apps yourself, then select them.")
            }
        case .moveSelectedFile:
            throw AgentError.invalid("Howdoey provides explanations and demonstrations only. File moves are unavailable.")
        case .wait: break
        }
    }
    public static func validateFolder(_ name: String) throws {
        guard !name.isEmpty, name.count <= 100, name != ".", name != "..", !name.contains("/"), !name.contains(":"), !name.contains("\\"), !name.contains(where: { $0.isNewline || $0.asciiValue.map { $0 < 32 } == true }), !name.hasPrefix(".") else {
            throw AgentError.invalid("Choose a visible folder name without path separators.")
        }
    }
    public static func endpoint(_ raw: String) throws -> URL {
        guard let url = URL(string: raw), url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              let host = url.host, url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)) else {
            throw AgentError.invalid("Use an HTTPS provider URL, or HTTP on localhost for a local model.")
        }
        return url
    }
}
