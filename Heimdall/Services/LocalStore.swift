import Foundation
import Observation

@MainActor @Observable
final class LocalStore {
    private(set) var annotations: [MapAnnotation] = []
    private(set) var media: [MediaItem] = []
    private(set) var reports: [SevenSReport] = []
    private(set) var isLoaded = false
    private(set) var ownPosition: PositionSnapshot?
    private(set) var callsign = ""
    let files: SecureFiles

    init(files: SecureFiles) { self.files = files }

    func load() throws {
        guard !isLoaded else { return }
        if FileManager.default.fileExists(atPath: files.journalURL.path) {
            let data = try Data(contentsOf: files.journalURL)
            let journal = try JSONDecoder().decode(FieldJournal.self, from: data)
            guard journal.version == 1, journal.annotations.count <= 10_000,
                journal.annotations.allSatisfy(\.isValid),
                Set(journal.annotations.map(\.id)).count == journal.annotations.count,
                Set(journal.media.map(\.id)).count == journal.media.count,
                journal.reports.count <= 10_000, journal.reports.allSatisfy(\.isValid),
                Set(journal.reports.map(\.id)).count == journal.reports.count,
                journal.ownPosition?.isValid ?? true,
                Self.isValidCallsign(journal.callsign ?? "")
            else { throw AppError.invalidState }
            annotations = journal.annotations
            media = journal.media
            reports = journal.reports
            ownPosition = journal.ownPosition
            callsign = journal.callsign ?? ""
        }
        try files.cleanStaging()
        isLoaded = true
    }

    private func commit(annotations: [MapAnnotation], media: [MediaItem], reports: [SevenSReport]? = nil) throws {
        guard isLoaded else { throw AppError.invalidState }
        let journal = FieldJournal(
            annotations: annotations, media: media, reports: reports ?? self.reports, ownPosition: ownPosition,
            callsign: callsign)
        try SecureFiles.write(JSONEncoder().encode(journal), to: files.journalURL)
        self.annotations = annotations
        self.media = media
        self.reports = journal.reports
    }

    func save(_ annotation: MapAnnotation) throws {
        guard annotation.isValid else { throw AppError.invalidState }
        var updated = annotations
        if let index = updated.firstIndex(where: { $0.id == annotation.id }) {
            updated[index] = annotation
        } else {
            guard updated.count < 10_000 else { throw AppError.invalidState }
            updated.append(annotation)
        }
        try commit(annotations: updated, media: media)
    }

    func deleteAnnotation(_ id: UUID) throws {
        try commit(annotations: annotations.filter { $0.id != id }, media: media)
    }

    func addMedia(_ item: MediaItem) throws {
        try commit(annotations: annotations, media: [item] + media)
    }

    func saveReport(_ report: SevenSReport) throws {
        guard report.isValid else { throw AppError.invalidState }
        var updated = reports
        if let index = updated.firstIndex(where: { $0.id == report.id }) {
            updated[index] = report
        } else {
            guard updated.count < 10_000 else { throw AppError.invalidState }
            updated.insert(report, at: 0)
        }
        try commit(annotations: annotations, media: media, reports: updated)
    }

    func deleteReport(_ id: UUID) throws {
        if let recording = reports.first(where: { $0.id == id })?.recording {
            let url = files.voiceDirectory.appendingPathComponent(recording.fileName)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        try commit(annotations: annotations, media: media, reports: reports.filter { $0.id != id })
    }

    func setOwnPosition(_ position: PositionSnapshot?) throws {
        guard isLoaded, position?.isValid ?? true else { throw AppError.invalidState }
        let journal = FieldJournal(
            annotations: annotations, media: media, reports: reports, ownPosition: position, callsign: callsign)
        try SecureFiles.write(JSONEncoder().encode(journal), to: files.journalURL)
        ownPosition = position
    }

    static func isValidCallsign(_ value: String) -> Bool {
        value.count <= 24 && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    func setCallsign(_ value: String) throws {
        guard isLoaded else { throw AppError.invalidState }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidCallsign(trimmed) else { throw AppError.invalidState }
        let journal = FieldJournal(
            annotations: annotations, media: media, reports: reports, ownPosition: ownPosition, callsign: trimmed)
        try SecureFiles.write(JSONEncoder().encode(journal), to: files.journalURL)
        callsign = trimmed
    }

    func deleteMedia(_ item: MediaItem) throws {
        // Remove bytes before the index entry. On failure the entry remains retryable.
        for name in [item.fileName, item.thumbnailName] {
            let url = files.mediaDirectory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        try commit(annotations: annotations, media: media.filter { $0.id != item.id })
    }
}
