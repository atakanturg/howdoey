import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let set = root.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let n = CGFloat(pixels)
        let rect = NSRect(x: n * 0.05, y: n * 0.05, width: n * 0.9, height: n * 0.9)
        let shape = NSBezierPath(roundedRect: rect, xRadius: n * 0.21, yRadius: n * 0.21)
        NSGradient(starting: NSColor(calibratedRed: 0.23, green: 0.42, blue: 0.98, alpha: 1), ending: NSColor(calibratedRed: 0.53, green: 0.25, blue: 0.91, alpha: 1))!.draw(in: shape, angle: 45)
        NSColor.white.setStroke()
        let path = NSBezierPath(); path.lineWidth = max(1.5, n * 0.05); path.lineCapStyle = .round; path.lineJoinStyle = .round
        for (x, y, dx, dy) in [(0.27, 0.27, 1.0, 1.0), (0.73, 0.27, -1.0, 1.0), (0.27, 0.73, 1.0, -1.0), (0.73, 0.73, -1.0, -1.0)] {
            path.move(to: CGPoint(x: n * (x + dx * 0.10), y: n * y)); path.line(to: CGPoint(x: n * x, y: n * y)); path.line(to: CGPoint(x: n * x, y: n * (y + dy * 0.10)))
        }
        path.stroke()
        NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: n * 0.42, y: n * 0.42, width: n * 0.16, height: n * 0.16)).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: set.appendingPathComponent(name))
    }
}
