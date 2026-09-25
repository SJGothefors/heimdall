import Foundation

struct MediaItem: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case photo, video }
    var id: UUID
    var kind: Kind
    var createdAt: Date
    var byteCount: Int64
    // Filenames are derived from UUIDs, never accepted from imported content.
    var fileName: String { id.uuidString + (kind == .photo ? ".jpg" : ".mov") }
    var thumbnailName: String { id.uuidString + "-thumb.jpg" }
    var isValid: Bool { byteCount > 0 && createdAt.timeIntervalSince1970.isFinite }
}
