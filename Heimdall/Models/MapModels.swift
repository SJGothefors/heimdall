import Foundation
import CoreGraphics

struct Coordinate: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-85...85).contains(latitude) && (-180...180).contains(longitude)
    }

    var worldPoint: CGPoint {
        CGPoint(x: (longitude + 180) / 360,
                y: (1 - asinh(tan(latitude * .pi / 180)) / .pi) / 2)
    }

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(worldPoint: CGPoint) {
        longitude = worldPoint.x * 360 - 180
        latitude = atan(sinh(.pi * (1 - 2 * worldPoint.y))) * 180 / .pi
    }

    var formatted: String {
        MGRS.string(for: self) ?? decimalDegrees
    }
    var decimalDegrees: String { String(format: "%.5f°, %.5f°", latitude, longitude) }
}

struct MapBounds: Codable, Equatable, Sendable {
    var west: Double
    var south: Double
    var east: Double
    var north: Double

    static let sweden = MapBounds(west: 10, south: 55, east: 25, north: 70)
    var topLeft: CGPoint { Coordinate(latitude: north, longitude: west).worldPoint }
    var bottomRight: CGPoint { Coordinate(latitude: south, longitude: east).worldPoint }
    var center: Coordinate {
        Coordinate(worldPoint: CGPoint(x: (topLeft.x + bottomRight.x) / 2, y: (topLeft.y + bottomRight.y) / 2))
    }

    func contains(_ c: Coordinate) -> Bool {
        c.isValid && (west...east).contains(c.longitude) && (south...north).contains(c.latitude)
    }

    var isValid: Bool {
        [west, south, east, north].allSatisfy(\.isFinite) && west < east && south < north &&
        west >= 9 && east <= 26 && south >= 54 && north <= 71
    }
}

enum TacticalLayer: String, Codable, CaseIterable, Identifiable, Sendable {
    case blue = "BLUE", red = "RED", tac = "TAC"
    var id: String { rawValue }
    var title: String {
        switch self { case .blue: "Friendly forces"; case .red: "Enemy forces"; case .tac: "Points of interest" }
    }
    var symbol: String {
        switch self { case .blue: "rectangle"; case .red: "diamond"; case .tac: "mappin" }
    }
}

enum AnnotationKind: String, Codable, CaseIterable, Sendable {
    case point, line, area
}

struct MapAnnotation: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var layer: TacticalLayer
    var kind: AnnotationKind
    var title: String
    var notes = ""
    var coordinates: [Coordinate]
    var createdAt = Date()

    var isValid: Bool {
        let minimum = kind == .point ? 1 : (kind == .line ? 2 : 3)
        return coordinates.count >= minimum && coordinates.count <= 10_000 &&
            Set(coordinates).count >= minimum &&
            (kind != .point || coordinates.count == 1) && coordinates.allSatisfy { MapBounds.sweden.contains($0) } &&
            title.count <= 80 && notes.count <= 2_000
    }
}

struct MapPackage: Codable, Sendable {
    struct Feature: Codable, Sendable {
        enum Kind: String, Codable, Sendable { case land, water, river, road }
        var kind: Kind
        var paths: [[Coordinate]]
    }
    struct Place: Codable, Sendable {
        var name: String
        var coordinate: Coordinate
        var population: Int
    }
    struct Elevation: Codable, Sendable {
        var columns: Int
        var rows: Int
        var meters: [Double]
    }
    var version: Int
    var name: String
    var detail: String
    var attribution: String
    var bounds: MapBounds
    var features: [Feature]
    var places: [Place]
    var elevation: Elevation

    func validate() throws {
        guard version == 1, bounds.isValid, name.count <= 100, detail.count <= 300, attribution.count <= 4_000,
              features.count <= 30_000, places.count <= 10_000,
              (2...512).contains(elevation.columns), (2...512).contains(elevation.rows),
              elevation.meters.count == elevation.columns * elevation.rows,
              elevation.meters.allSatisfy({ $0.isFinite && (-12_000...10_000).contains($0) }) else {
            throw AppError.invalidMap
        }
        var count = 0
        for feature in features {
            for path in feature.paths {
                count += path.count
                guard count <= 300_000, path.count >= 2, path.allSatisfy({ bounds.contains($0) }) else {
                    throw AppError.invalidMap
                }
            }
        }
        guard places.allSatisfy({ bounds.contains($0.coordinate) && $0.name.count <= 120 }) else {
            throw AppError.invalidMap
        }
    }
}

enum AppError: LocalizedError {
    case invalidMap, invalidState, missingMap, cameraUnavailable, invalidMedia
    var errorDescription: String? {
        switch self {
        case .invalidMap: "This map pack is invalid or exceeds the supported limits. Your existing map has not changed."
        case .invalidState: "The local journal could not be read safely. Existing files have been preserved."
        case .missingMap: "The bundled Sweden map is missing. Reinstall the application build."
        case .cameraUnavailable: "A camera is not available on this device. Use a physical iPhone to capture media."
        case .invalidMedia: "The captured media could not be saved. Check available storage and try again."
        }
    }
}
