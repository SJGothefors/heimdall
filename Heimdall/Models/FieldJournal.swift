import Foundation

/// Version 1 remains readable when optional fields are added. Validate on both
/// load and save so the app cannot write a journal it would refuse to reopen.
struct FieldJournal: Codable {
    static let maximumItems = 10_000
    static let maximumBytes = 64 * 1_024 * 1_024

    var version = 1
    var annotations: [MapAnnotation] = []
    var media: [MediaItem] = []
    var reports: [SevenSReport] = []
    var ownPosition: PositionSnapshot?
    var callsign: String?
    var pendingDeletions: [AttachmentFile]?

    func validate() throws {
        let recordings = reports.compactMap(\.recording)
        let deletions = pendingDeletions ?? []
        let retainedFiles = Set(
            media.flatMap(AttachmentFile.files) + recordings.map(AttachmentFile.voice))
        guard version == 1,
            annotations.count <= Self.maximumItems, annotations.allSatisfy(\.isValid),
            Set(annotations.map(\.id)).count == annotations.count,
            media.count <= Self.maximumItems, media.allSatisfy(\.isValid),
            Set(media.map(\.id)).count == media.count,
            reports.count <= Self.maximumItems, reports.allSatisfy(\.isValid),
            Set(reports.map(\.id)).count == reports.count,
            Set(recordings.map(\.id)).count == recordings.count,
            ownPosition?.isValid ?? true, Self.isValidCallsign(callsign ?? ""),
            deletions.count <= Self.maximumItems * 3,
            Set(deletions).count == deletions.count, retainedFiles.isDisjoint(with: deletions)
        else { throw AppError.invalidState }
    }

    static func isValidCallsign(_ value: String) -> Bool {
        value.count <= 24
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

/// Only UUID-derived attachment paths can be scheduled for deletion.
struct AttachmentFile: Codable, Hashable {
    enum Kind: String, Codable { case photo, video, thumbnail, voice }
    let id: UUID
    let kind: Kind

    static func files(for item: MediaItem) -> [Self] {
        [
            Self(id: item.id, kind: item.kind == .photo ? .photo : .video),
            Self(id: item.id, kind: .thumbnail),
        ]
    }

    static func voice(_ recording: VoiceRecording) -> Self { Self(id: recording.id, kind: .voice) }

    func url(in files: SecureFiles) -> URL {
        let suffix: String
        switch kind {
        case .photo: suffix = ".jpg"
        case .video: suffix = ".mov"
        case .thumbnail: suffix = "-thumb.jpg"
        case .voice: suffix = ".m4a"
        }
        return (kind == .voice ? files.voiceDirectory : files.mediaDirectory)
            .appendingPathComponent(id.uuidString + suffix)
    }
}
