import Foundation
import CoreGraphics

struct MapViewport {
    var center = MapBounds.sweden.center.worldPoint
    var zoom = 4.5
    var scale: Double { 256 * pow(2, zoom) }

    func screenPoint(_ coordinate: Coordinate, size: CGSize) -> CGPoint {
        let p = coordinate.worldPoint
        return CGPoint(x: (p.x - center.x) * scale + size.width / 2,
                       y: (p.y - center.y) * scale + size.height / 2)
    }

    func coordinate(at point: CGPoint, size: CGSize) -> Coordinate {
        Coordinate(worldPoint: CGPoint(x: center.x + (point.x - size.width / 2) / scale,
                                       y: center.y + (point.y - size.height / 2) / scale))
    }

    mutating func fit(_ bounds: MapBounds, size: CGSize) {
        center = bounds.center.worldPoint
        let width = bounds.bottomRight.x - bounds.topLeft.x
        let height = bounds.bottomRight.y - bounds.topLeft.y
        zoom = log2(max(1, min((size.width - 64) / width, (size.height - 110) / height)) / 256)
        clamp()
    }

    mutating func clamp() {
        zoom = min(16, max(3, zoom))
        center.x = min(MapBounds.sweden.bottomRight.x, max(MapBounds.sweden.topLeft.x, center.x))
        center.y = min(MapBounds.sweden.bottomRight.y, max(MapBounds.sweden.topLeft.y, center.y))
    }

    var metersPerPoint: Double {
        40_075_016.686 * cos(Coordinate(worldPoint: center).latitude * .pi / 180) / scale
    }
}
