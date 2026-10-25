// Coordinate helpers. The backend speaks global Quartz points (origin top-left of the primary display).
// AppKit windows use Cocoa points (origin bottom-left of the primary display). Points are used everywhere,
// so Retina scaling is the capture layer's concern and never leaks into UI math.
import AppKit

enum ScreenGeometry {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    /// Quartz position of a screen's top-left corner.
    static func quartzOrigin(of frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX, y: primaryHeight - frame.maxY)
    }
    static var unionFrame: CGRect {
        NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
    }
}

struct WindowTarget {
    let rect: CGRect // global Quartz points
    let pid: pid_t
}

enum WindowHitTest {
    /// Frontmost normal window under a Quartz point, ignoring Howdoey's own windows.
    static func topWindow(at point: CGPoint) -> WindowTarget? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        for window in list { // ordered front to back
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? Int, pid != me,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width > 40, rect.height > 40, rect.contains(point) else { continue }
            return WindowTarget(rect: rect, pid: pid_t(pid))
        }
        return nil
    }
}
