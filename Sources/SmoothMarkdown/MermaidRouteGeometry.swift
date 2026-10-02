import SwiftUI

/// Pure path construction keeps arrow directions tied to actual endpoint legs.
enum MermaidRouteGeometry {
    static func path(_ points: [CGPoint], routing: MermaidEdgeRouting, radius: CGFloat) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }
        if routing == .straight || points.count == 2 || radius == 0 {
            for point in points.dropFirst() { path.addLine(to: point) }
            return path
        }
        for index in 1..<(points.count - 1) {
            let previous = points[index - 1], corner = points[index], next = points[index + 1]
            let before = hypot(corner.x - previous.x, corner.y - previous.y)
            let after = hypot(next.x - corner.x, next.y - corner.y)
            guard before > 0, after > 0 else { continue }
            let limit = min(before, after) / 2
            let bend = routing == .curved ? limit : min(radius, limit)
            let enter = CGPoint(x: corner.x + (previous.x - corner.x) * bend / before,
                                y: corner.y + (previous.y - corner.y) * bend / before)
            let leave = CGPoint(x: corner.x + (next.x - corner.x) * bend / after,
                                y: corner.y + (next.y - corner.y) * bend / after)
            path.addLine(to: enter)
            path.addQuadCurve(to: leave, control: corner)
        }
        path.addLine(to: points.last!)
        return path
    }
}
