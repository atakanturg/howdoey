// Howdoey logo, drawn natively from howdoey-logo.svg (40×40 viewBox) so it needs no bundled resources
// and stays sharp at any size. Geometry below mirrors the SVG paths exactly.
import AppKit
import SwiftUI

enum Brand {
    static let blue = Color(red: 0x21 / 255, green: 0x58 / 255, blue: 0xA0 / 255)
    static let nsBlue = NSColor(red: 0x21 / 255, green: 0x58 / 255, blue: 0xA0 / 255, alpha: 1)

    // SVG elliptical arc with equal radii, small-arc, sweep=1 (clockwise on screen), flattened to line segments.
    private static func arc(_ path: CGMutablePath, to end: CGPoint, radius r: CGFloat) {
        let start = path.currentPoint
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let dx = end.x - start.x, dy = end.y - start.y
        let chord = hypot(dx, dy)
        let d = sqrt(max(r * r - chord * chord / 4, 0))
        let center = CGPoint(x: mid.x + d * (-dy / chord), y: mid.y + d * (dx / chord))
        let a0 = atan2(start.y - center.y, start.x - center.x)
        var a1 = atan2(end.y - center.y, end.x - center.x)
        if a1 < a0 { a1 += 2 * .pi }
        for i in 1...24 {
            let a = a0 + (a1 - a0) * CGFloat(i) / 24
            path.addLine(to: CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a)))
        }
    }

    /// The speech bubble (filled).
    static let bubble: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 7, y: 9.5))
        arc(p, to: CGPoint(x: 12.5, y: 4), radius: 5.5)
        p.addLine(to: CGPoint(x: 27.5, y: 4))
        arc(p, to: CGPoint(x: 33, y: 9.5), radius: 5.5)
        p.addLine(to: CGPoint(x: 33, y: 24.5))
        arc(p, to: CGPoint(x: 27.5, y: 30), radius: 5.5)
        p.addLine(to: CGPoint(x: 19, y: 30))
        p.addLine(to: CGPoint(x: 10, y: 36))
        p.addLine(to: CGPoint(x: 10, y: 28.8))
        arc(p, to: CGPoint(x: 7, y: 24), radius: 5.5)
        p.closeSubpath()
        return p
    }()
    /// The question-mark hook (stroked, 2.7 wide, round caps).
    static let question: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 16.5, y: 13.5))
        arc(p, to: CGPoint(x: 23.5, y: 14.4), radius: 3.7)
        p.addCurve(to: CGPoint(x: 20, y: 19.5), control1: CGPoint(x: 23.5, y: 16.9), control2: CGPoint(x: 20, y: 16.9))
        return p
    }()
    static let dot = CGRect(x: 18.6, y: 22.6, width: 2.8, height: 2.8)

    /// Menu bar icon: a template image (macOS tints it) with the question mark cut out of the bubble.
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let scale = min(rect.width, rect.height) / 40
            ctx.scaleBy(x: scale, y: scale)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(bubble); ctx.fillPath()
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(3.4); ctx.setLineCap(.round)
            ctx.addPath(question); ctx.strokePath()
            ctx.fillEllipse(in: dot.insetBy(dx: -0.4, dy: -0.4))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Howdoey"
        return image
    }
}

/// Full-colour logo for in-app use.
struct BrandMark: View {
    var size: CGFloat = 24
    var body: some View {
        Canvas { context, canvas in
            let scale = min(canvas.width, canvas.height) / 40
            context.scaleBy(x: scale, y: scale)
            context.fill(Path(Brand.bubble), with: .color(Brand.blue))
            context.stroke(Path(Brand.question), with: .color(.white), style: StrokeStyle(lineWidth: 2.7, lineCap: .round))
            context.fill(Path(ellipseIn: Brand.dot), with: .color(.white))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
