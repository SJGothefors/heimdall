import Foundation
import Observation

/// The only journal writer. A successful disk commit always precedes UI changes.
@MainActor @Observable
final class LocalStore {
    private var journal = FieldJournal()
    private(set) var isLoaded = false
    private(set) var cleanupError: String?
    let files: SecureFiles

    var annotations: [MapAnnotation] { journal.annotations }
    var media: [MediaItem] { journal.media }
    var reports: [SevenSReport] { journal.reports }
    var ownPosition: PositionSnapshot? { journal.ownPosition }
    var callsign: String { journal.callsign ?? "" }

    init(files: SecureFiles) { self.files = files }

    func load() throws {
        guard !isLoaded else { return }
        var loaded = FieldJournal()
        do {
            let values = try files.journalURL.resourceValues(forKeys: [
                .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                let size = values.fileSize, size <= FieldJournal.maximumBytes
            else { throw AppError.invalidState }
            loaded = try JSONDecoder().decode(FieldJournal.self, from: Data(contentsOf: files.journalURL))
            try loaded.validate()
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain
            && error.code == NSFileReadNoSuchFileError
        {
            // Only an absent journal means a new notebook. Access failures,
            // including locked-device protection, must never load empty state.
        }
        try files.cleanStaging()
        journal = loaded
        isLoaded = true
        retryPendingDeletions()
    }

    private func commit(_ edit: (inout FieldJournal) -> Void) throws {
        guard isLoaded else { throw AppError.invalidState }
        var updated = journal
        edit(&updated)
        try updated.validate()
        let data = try JSONEncoder().encode(updated)
        guard data.count <= FieldJournal.maximumBytes else { throw AppError.journalFull }
        try SecureFiles.write(data, to: files.journalURL)
        journal = updated
    }

    func save(_ annotation: MapAnnotation) throws {
        try commit { journal in
            if let index = journal.annotations.firstIndex(where: { $0.id == annotation.id }) {
                journal.annotations[index] = annotation
            } else {
                journal.annotations.append(annotation)
            }
        }
    }

    func deleteAnnotation(_ id: UUID) throws {
        try commit { $0.annotations.removeAll { $0.id == id } }
    }

    func addMedia(_ item: MediaItem) throws {
        try commit { $0.media.insert(item, at: 0) }
    }

    func saveReport(_ report: SevenSReport) throws {
        try commit { journal in
            if let index = journal.reports.firstIndex(where: { $0.id == report.id }) {
                if let old = journal.reports[index].recording, old.id != report.recording?.id {
                    journal.pendingDeletions = (journal.pendingDeletions ?? []) + [.voice(old)]
                }
                journal.reports[index] = report
            } else {
                journal.reports.insert(report, at: 0)
            }
        }
        retryPendingDeletions()
    }

    func deleteReport(_ id: UUID) throws {
        try commit { journal in
            if let recording = journal.reports.first(where: { $0.id == id })?.recording {
                journal.pendingDeletions = (journal.pendingDeletions ?? []) + [.voice(recording)]
            }
            journal.reports.removeAll { $0.id == id }
        }
        try finishDeletion()
    }

    func setOwnPosition(_ position: PositionSnapshot?) throws {
        try commit { $0.ownPosition = position }
    }

    static func isValidCallsign(_ value: String) -> Bool { FieldJournal.isValidCallsign(value) }

    func setCallsign(_ value: String) throws {
        try commit { $0.callsign = value.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func deleteMedia(_ item: MediaItem) throws {
        try commit { journal in
            if let saved = journal.media.first(where: { $0.id == item.id }) {
                journal.pendingDeletions =
                    (journal.pendingDeletions ?? []) + AttachmentFile.files(for: saved)
                journal.media.removeAll { $0.id == saved.id }
            }
        }
        try finishDeletion()
    }

    private func finishDeletion() throws {
        retryPendingDeletions()
        if cleanupError != nil { throw AppError.attachmentCleanupPending }
    }

    /// Persist intent first. A crash or locked-device failure can then resume
    /// cleanup without deleting files still referenced by a saved report.
    func retryPendingDeletions() {
        guard isLoaded else { return }
        do {
            let pending = journal.pendingDeletions ?? []
            if !pending.isEmpty {
                for attachment in pending {
                    let url = attachment.url(in: files)
                    do {
                        try FileManager.default.removeItem(at: url)
                    } catch let error as NSError
                        where error.domain == NSCocoaErrorDomain
                        && error.code == NSFileNoSuchFileError
                    {
                        // A previous cleanup may have removed the file before a crash.
                    }
                }
                try commit { $0.pendingDeletions = nil }
            }
            cleanupError = nil
        } catch {
            cleanupError = AppError.attachmentCleanupPending.localizedDescription
        }
    }
}
