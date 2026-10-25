import Foundation

public struct GuideCandidate {
    public let id: Int
    public let label: String
    public init(id: Int, label: String) { self.id = id; self.label = label }
}
public enum GuideTargetResolver {
    private static func normalized(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }
    public static func resolve(_ action: AgentAction, candidates: [GuideCandidate]) -> AgentAction? {
        guard action.kind == .press || action.kind == .setValue else { return action }
        let label = action.targetLabel.map(normalized)
        let matched: GuideCandidate?
        if let id = action.target, let exact = candidates.first(where: { $0.id == id }),
           label == nil || label == normalized(exact.label) { matched = exact }
        else if let label, !label.isEmpty {
            let matches = candidates.filter { normalized($0.label) == label }
            matched = matches.count == 1 ? matches.first : nil
        } else { matched = nil }
        guard let matched else { return nil }
        return AgentAction(kind: action.kind, target: matched.id, value: action.value, targetLabel: matched.label)
    }
}
