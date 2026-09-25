import Foundation

struct PositionSnapshot: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable { case gps, manual }
    var coordinate: Coordinate
    var source: Source
    var timestamp: Date
    var accuracy: Double?
    var isValid: Bool {
        MapBounds.sweden.contains(coordinate) && timestamp.timeIntervalSince1970.isFinite
            && (accuracy.map { $0.isFinite && $0 >= 0 } ?? true)
    }
}
