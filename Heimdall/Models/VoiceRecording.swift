import Foundation

struct VoiceRecording: Codable, Equatable, Sendable {
    var id: UUID
    var recordedAt: Date
    var duration: TimeInterval
    var position: PositionSnapshot?
    var language: String
    var fileName: String { id.uuidString + ".m4a" }
    var isValid: Bool {
        recordedAt.timeIntervalSince1970.isFinite && duration.isFinite && duration > 0 && duration <= 301
            && ["sv-SE", "en-US"].contains(language) && (position?.isValid ?? true)
    }
}
