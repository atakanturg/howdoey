import Foundation

/// A prediction is only a reason to obtain a fresh observation, never proof of success.
public struct ProgressExpectation: Codable {
    public enum Kind: String, Codable { case appears, disappears, valueChanges, windowChanges, manual }
    public let kind: Kind
    public let label: String?
    public init(kind: Kind, label: String? = nil) { self.kind = kind; self.label = label }
    public func shouldObserve(before: [String: String], after: [String: String], previousWindow: String, currentWindow: String) -> Bool {
        switch kind {
        case .manual: return false
        case .windowChanges: return !currentWindow.isEmpty && currentWindow != previousWindow
        case .appears:
            guard let label, !label.isEmpty else { return false }
            return before[label] == nil && after[label] != nil
        case .disappears:
            guard let label, !label.isEmpty else { return false }
            return before[label] != nil && after[label] == nil
        case .valueChanges:
            guard let label, !label.isEmpty, let old = before[label], let new = after[label] else { return false }
            return old != new
        }
    }
}
