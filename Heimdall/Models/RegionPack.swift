import Foundation

struct RegionManifest: Codable, Identifiable, Equatable, Sendable {
    var version: Int
    var id: String
    var name: String
    var schema: String
    var bounds: MapBounds
    var focus: Coordinate
    var sourceDate: String
    var attribution: String
    var sourceURL: String
    var sha256: String
    var imagerySHA256: String?

    func validate() throws {
        guard version == 1, schema == "protomaps-v4",
            id.range(of: "^[a-z0-9-]{1,60}$", options: .regularExpression) != nil,
            !name.isEmpty, name.count <= 100, bounds.isValid, bounds.contains(focus),
            sourceDate.count <= 40, attribution.count <= 2000, !attribution.isEmpty, sourceURL.count <= 1000,
            sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
            imagerySHA256 == nil || imagerySHA256?.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
        else { throw AppError.invalidMap }
    }
}

struct RegionPack: Identifiable, Sendable {
    let manifest: RegionManifest
    let archiveURL: URL
    let byteCount: Int64
    let bundled: Bool
    var id: String { manifest.id }
}
