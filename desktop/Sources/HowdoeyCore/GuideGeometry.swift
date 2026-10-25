import Foundation
import CoreGraphics

public enum GuideGeometry {
    /// Keep the controls at a screen edge, choosing the corner farthest from
    /// the demonstrated control. Geometry is in the caller's coordinate space.
    public static func sidePanel(in visible: CGRect, size: CGSize, avoiding target: CGRect?) -> CGRect {
        let area = visible.insetBy(dx:12,dy:12)
        let width = min(size.width,area.width), height = min(size.height,area.height)
        let corners = [CGPoint(x:area.minX,y:area.minY),CGPoint(x:area.minX,y:area.maxY-height),
                       CGPoint(x:area.maxX-width,y:area.minY),CGPoint(x:area.maxX-width,y:area.maxY-height)]
        guard let target else { return CGRect(origin:corners[3],size:CGSize(width:width,height:height)) }
        let halo = target.insetBy(dx:-50,dy:-50)
        return corners.map { CGRect(origin:$0,size:CGSize(width:width,height:height)) }.max { a,b in
            func score(_ frame: CGRect) -> CGFloat {
                let overlap = frame.intersection(halo)
                let penalty = overlap.isNull ? 0 : overlap.width*overlap.height*1000
                return pow(frame.midX-target.midX,2)+pow(frame.midY-target.midY,2)-penalty
            }
            return score(a) < score(b)
        }!
    }
    // Reject page-sized groups: pointing at their centre looks like a guessed click.
    public static func isCompactTarget(_ rect: CGRect, in viewport: CGRect) -> Bool {
        let numbers = [rect.minX, rect.minY, rect.width, rect.height, viewport.width, viewport.height]
        guard numbers.allSatisfy({ $0.isFinite }), rect.width >= 4, rect.height >= 4,
              rect.width <= 480, rect.height <= 140, rect.width * rect.height <= 50000,
              !viewport.isEmpty else { return false }
        let visible = rect.intersection(viewport)
        return !visible.isNull && visible.width * visible.height >= rect.width * rect.height * 0.8
    }
}
