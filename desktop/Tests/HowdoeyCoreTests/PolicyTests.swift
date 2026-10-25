import Foundation
import CoreGraphics
import HowdoeyCore
final class PolicyTests {
    func testGuideRejectsPageSizedAndOffscreenTargets() {
        let window = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertFalse(GuideGeometry.isCompactTarget(window, in: window))
        XCTAssertFalse(GuideGeometry.isCompactTarget(CGRect(x: 40, y: 50, width: 800, height: 600), in: window))
        XCTAssertFalse(GuideGeometry.isCompactTarget(CGRect(x: 1400, y: 20, width: 120, height: 40), in: window))
        XCTAssertTrue(GuideGeometry.isCompactTarget(CGRect(x: 24, y: 150, width: 124, height: 48), in: window))
        let secondary = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        XCTAssertTrue(GuideGeometry.isCompactTarget(CGRect(x: -1400, y: -150, width: 124, height: 48), in: secondary))
    }
    func testGuideTargetRepairRequiresAnExactUnambiguousLabel() {
        let candidates = [GuideCandidate(id: 7, label: "Attach files"), GuideCandidate(id: 9, label: "Send")]
        XCTAssertEqual(GuideTargetResolver.resolve(.init(kind: .press, target: 99, targetLabel: "Attach files"), candidates: candidates)?.target, 7)
        XCTAssertEqual(GuideTargetResolver.resolve(.init(kind: .press, target: 9, targetLabel: "Attach files"), candidates: candidates)?.target, 7)
        XCTAssertTrue(GuideTargetResolver.resolve(.init(kind: .press, target: 99), candidates: candidates) == nil)
        XCTAssertTrue(GuideTargetResolver.resolve(.init(kind: .press, target: 99, targetLabel: "Compose"), candidates: candidates) == nil)
        XCTAssertTrue(GuideTargetResolver.resolve(.init(kind: .press, targetLabel: "Attach files"), candidates: candidates + [GuideCandidate(id: 10, label: "Attach files")]) == nil)
    }
    func testProgressWaitsForRelevantChange() {
        let plan = ProgressExpectation(kind: .appears, label: "Open")
        let before = ["Attach files":"", "Inbox":"14"]
        XCTAssertFalse(plan.shouldObserve(before: before, after: ["Attach files":"", "Inbox":"15"], previousWindow: "Mail", currentWindow: "Mail"))
        XCTAssertTrue(plan.shouldObserve(before: before, after: ["Attach files":"", "Open":""], previousWindow: "Mail", currentWindow: "Mail"))
        XCTAssertFalse(plan.shouldObserve(before: ["Open":""], after: ["Open":""], previousWindow: "Mail", currentWindow: "Mail"))
        XCTAssertFalse(ProgressExpectation(kind: .manual).shouldObserve(before: before, after: [:], previousWindow: "A", currentWindow: "B"))
        XCTAssertTrue(ProgressExpectation(kind: .valueChanges,label: "Dark").shouldObserve(before: ["Dark":"0"], after: ["Dark":"1"], previousWindow: "Settings", currentWindow: "Settings"))
    }
    func testSidePanelAvoidsTargets() {
        let screen = CGRect(x:0,y:0,width:1512,height:960)
        for target in [CGRect(x:40,y:40,width:30,height:30),CGRect(x:1400,y:820,width:40,height:40)] {
            let panel = GuideGeometry.sidePanel(in:screen,size:CGSize(width:344,height:230),avoiding:target)
            XCTAssertTrue(screen.contains(panel))
            XCTAssertFalse(panel.intersects(target.insetBy(dx:-50,dy:-50)))
        }
        let small = CGRect(x:-800,y:0,width:800,height:600)
        XCTAssertTrue(small.contains(GuideGeometry.sidePanel(in:small,size:CGSize(width:344,height:230),avoiding:nil)))
    }
    func testAskCannotAct() {
        XCTAssertEqual(Mode.allCases, [.ask, .show])
        XCTAssertThrowsError(try Policy.validate(.init(kind: .press, target: 1), mode: .ask, validTargets: [1]))
        XCTAssertThrowsError(try Policy.validate(.init(kind: .moveSelectedFile), mode: .show, validTargets: []))
    }
    func testRejectsStaleTargetsAndUnsafeApps() {
        XCTAssertThrowsError(try Policy.validate(.init(kind: .press, target: 2), mode: .show, validTargets: [1]))
        XCTAssertThrowsError(try Policy.validate(.init(kind: .openApplication, bundleID: "com.apple.Terminal"), mode: .show, validTargets: []))
    }
    func testRejectsTraversalAndRemoteHTTP() {
        for name in ["../secret", ".hidden", "..", "a/b", "a\\b", ""] { XCTAssertThrowsError(try Policy.validateFolder(name)) }
        XCTAssertThrowsError(try Policy.endpoint("http://example.com/v1"))
        XCTAssertThrowsError(try Policy.endpoint("https://secret@example.com/v1"))
        XCTAssertNoThrow(try Policy.endpoint("http://localhost:11434/v1"))
    }
    func testMalformedModelDecision() {
        XCTAssertThrowsError(try Decision.parse("I clicked it"))
        XCTAssertThrowsError(try Decision.parse(#"{"message":"done","done":true,"action":{"kind":"wait"}}"#))
    }
    func testExistingFolderAndCollisionRecovery() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let inbox = root.appendingPathComponent("inbox")
        let dest = root.appendingPathComponent("sorted")
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        try fm.createDirectory(at: dest.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        let source = inbox.appendingPathComponent("note.txt")
        try Data("keep me".utf8).write(to: source)
        try Data("original".utf8).write(to: dest.appendingPathComponent("Documents/note.txt"))
        let target = try FileOrganizer.destination(source: source, root: dest, folder: "Documents")
        XCTAssertEqual(target.lastPathComponent, "note 2.txt")
        let receipt = try FileOrganizer.move(source: source, destination: target, expectedDigest: FileOrganizer.digest(source))
        try XCTAssertEqual(try String(contentsOf: receipt.destination), "keep me")
        try XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("Documents/note.txt")), "original")
        XCTAssertFalse(fm.fileExists(atPath: source.path))
    }
    func testFileChangedAfterApprovalIsRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("a.txt")
        try Data("one".utf8).write(to: source)
        let hash = try FileOrganizer.digest(source)
        try Data("two".utf8).write(to: source)
        XCTAssertThrowsError(try FileOrganizer.move(source: source, destination: root.appendingPathComponent("b.txt"), expectedDigest: hash))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testSymlinkDestinationEscapingRootIsRejected() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: fm.temporaryDirectory)
        XCTAssertThrowsError(try FileOrganizer.destination(source: root.appendingPathComponent("a.txt"), root: root, folder: "escape"))
    }
}


// Lightweight assertion runner so the same checks work with Apple's Command Line Tools,
// which ship Swift but do not include XCTest. No network or macOS permissions required.
private var failures = 0
private func failure(_ text: String, file: StaticString, line: UInt) {
    failures += 1
    print("FAIL: \(text) at \(file):\(line)")
}
private func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) rethrows {
    if try !value() { failure("expected true", file: file, line: line) }
}
private func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) rethrows {
    if try value() { failure("expected false", file: file, line: line) }
}
private func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) rethrows {
    if try lhs() != rhs() { failure("values differ", file: file, line: line) }
}
private func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try value(); failure("expected an error", file: file, line: line) } catch { }
}
private func XCTAssertNoThrow<T>(_ value: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try value() } catch { failure("unexpected error: \(error)", file: file, line: line) }
}
@main enum Checks {
    static func main() {
        let tests = PolicyTests()
        let cases: [(String, () throws -> Void)] = [
            ("Guide rejects page-sized and offscreen targets", tests.testGuideRejectsPageSizedAndOffscreenTargets),
            ("Guide ID repair requires an exact unique label", tests.testGuideTargetRepairRequiresAnExactUnambiguousLabel),
            ("Progress checks require the predicted change", tests.testProgressWaitsForRelevantChange),
            ("Side controls avoid highlighted targets", tests.testSidePanelAvoidsTargets),
            ("Ask cannot act", tests.testAskCannotAct),
            ("Stale targets and unsafe apps rejected", tests.testRejectsStaleTargetsAndUnsafeApps),
            ("Traversal and insecure endpoints rejected", tests.testRejectsTraversalAndRemoteHTTP),
            ("Malformed model decisions rejected", tests.testMalformedModelDecision),
            ("Existing folder and filename collision recovery", tests.testExistingFolderAndCollisionRecovery),
            ("Changed source rejected", tests.testFileChangedAfterApprovalIsRejected),
            ("Symlink escape rejected", tests.testSymlinkDestinationEscapingRootIsRejected)
        ]
        for (name, run) in cases {
            let before = failures
            do { try run() } catch { failure("\(name): \(error)", file: #filePath, line: #line) }
            if failures == before { print("PASS: \(name)") }
        }
        print("\(cases.count) checks; \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
