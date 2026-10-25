import Foundation
import CryptoKit

public struct FileReceipt: Sendable {
    public let source: URL
    public let destination: URL
    public let digest: String
}
public enum FileOrganizer {
    public static func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func destination(source: URL, root: URL, folder: String?) throws -> URL {
        if let folder { try Policy.validateFolder(folder) }
        let fm = FileManager.default
        let base = folder.map { root.appendingPathComponent($0, isDirectory: true) } ?? root
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedBase = base.resolvingSymlinksInPath().standardizedFileURL.path
        guard resolvedBase == resolvedRoot || resolvedBase.hasPrefix(resolvedRoot + "/") else { throw AgentError.invalid("The destination folder resolves outside the approved location.") }
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: base.path, isDirectory: &isDirectory), !isDirectory.boolValue { throw AgentError.invalid("A file already uses that folder name. Choose another name.") }
        let candidate = base.appendingPathComponent(source.lastPathComponent)
        guard candidate.standardizedFileURL != source.standardizedFileURL else { throw AgentError.invalid("That file is already in the requested folder.") }
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent
        for index in 2...1000 {
            let next = base.appendingPathComponent("\(stem) \(index)" + (ext.isEmpty ? "" : ".\(ext)"))
            if !fm.fileExists(atPath: next.path) { return next }
        }
        throw AgentError.invalid("Too many similarly named files exist in this folder.")
    }
    public static func move(source: URL, destination: URL, expectedDigest: String) throws -> FileReceipt {
        let fm = FileManager.default
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw AgentError.invalid("Choose a regular file, not a folder or symbolic link.") }
        guard try digest(source) == expectedDigest else { throw AgentError.invalid("The selected file changed after approval. Select it again.") }
        guard !fm.fileExists(atPath: destination.path) else { throw AgentError.invalid("The destination appeared after approval. Re-plan to choose a new name.") }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: source, to: destination)
        guard !fm.fileExists(atPath: source.path), try digest(destination) == expectedDigest else { throw AgentError.invalid("The move could not be verified. Inspect both locations before continuing.") }
        return FileReceipt(source: source, destination: destination, digest: expectedDigest)
    }
}
