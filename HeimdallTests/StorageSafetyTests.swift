import XCTest

@testable import Heimdall

@MainActor final class StorageSafetyTests: XCTestCase {
    private func files() throws -> SecureFiles {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try SecureFiles(root: root)
    }

    func testFailedJournalCommitKeepsAudioMediaAndPublishedState() throws {
        let files = try files()
        let store = LocalStore(files: files)
        try store.load()
        var report = SevenSReport()
        let audio = VoiceRecording(id: UUID(), recordedAt: .now, duration: 3, language: "sv-SE")
        report.recording = audio
        try store.saveReport(report)
        let media = MediaItem(id: UUID(), kind: .photo, createdAt: .now, byteCount: 4)
        try store.addMedia(media)
        let attachments = [AttachmentFile.voice(audio)] + AttachmentFile.files(for: media)
        let bytes = Data("test".utf8)
        for attachment in attachments { try SecureFiles.write(bytes, to: attachment.url(in: files)) }
        let original = try Data(contentsOf: files.journalURL)

        // A directory at the destination makes the final rename fail after the
        // replacement has been written. Keep the original for a reload check.
        let saved = files.root.appendingPathComponent("saved-journal.json")
        try FileManager.default.moveItem(at: files.journalURL, to: saved)
        try SecureFiles.createDirectory(files.journalURL)
        XCTAssertThrowsError(try store.deleteReport(report.id))
        XCTAssertThrowsError(try store.deleteMedia(media))
        XCTAssertThrowsError(try store.setCallsign("UNSAVED"))
        XCTAssertEqual(store.reports, [report])
        XCTAssertEqual(store.media, [media])
        XCTAssertEqual(store.callsign, "")
        for attachment in attachments {
            XCTAssertEqual(try Data(contentsOf: attachment.url(in: files)), bytes)
        }
        XCTAssertEqual(try Data(contentsOf: saved), original)
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: files.root.path).contains {
                $0.hasPrefix(".write-")
            })
        try FileManager.default.removeItem(at: files.journalURL)
        try FileManager.default.moveItem(at: saved, to: files.journalURL)
        let reopened = LocalStore(files: files)
        try reopened.load()
        XCTAssertEqual(reopened.reports, [report])
        XCTAssertEqual(reopened.media, [media])
    }

    func testPendingDeletionResumesAfterRelaunchAndKeepsUnknownRecordings() throws {
        let files = try files()
        let audio = VoiceRecording(id: UUID(), recordedAt: .now, duration: 3, language: "sv-SE")
        let media = MediaItem(id: UUID(), kind: .video, createdAt: .now, byteCount: 4)
        let pending = [AttachmentFile.voice(audio)] + AttachmentFile.files(for: media)
        // One missing file represents a crash partway through cleanup.
        for attachment in pending.dropFirst() {
            try SecureFiles.write(Data("test".utf8), to: attachment.url(in: files))
        }
        let orphan = files.voiceDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        try SecureFiles.write(Data("unsaved recording".utf8), to: orphan)
        let journal = FieldJournal(pendingDeletions: pending)
        try SecureFiles.write(JSONEncoder().encode(journal), to: files.journalURL)
        let store = LocalStore(files: files)
        try store.load()
        XCTAssertNil(store.cleanupError)
        for attachment in pending {
            XCTAssertFalse(FileManager.default.fileExists(atPath: attachment.url(in: files).path))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
        let restored = try JSONDecoder().decode(
            FieldJournal.self, from: Data(contentsOf: files.journalURL))
        XCTAssertNil(restored.pendingDeletions)
    }

    func testDeletionCannotRunBeforeJournalLoads() throws {
        let files = try files()
        let item = MediaItem(id: UUID(), kind: .photo, createdAt: .now, byteCount: 4)
        let url = files.mediaDirectory.appendingPathComponent(item.fileName)
        try SecureFiles.write(Data("test".utf8), to: url)
        XCTAssertThrowsError(try LocalStore(files: files).deleteMedia(item))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testInvalidMediaAndSharedAudioCannotCorruptJournal() throws {
        let files = try files()
        let store = LocalStore(files: files)
        try store.load()
        let item = MediaItem(id: UUID(), kind: .photo, createdAt: .now, byteCount: 4)
        try store.addMedia(item)
        var report = SevenSReport()
        report.recording = VoiceRecording(id: UUID(), recordedAt: .now, duration: 3, language: "en-US")
        try store.saveReport(report)
        let original = try Data(contentsOf: files.journalURL)
        XCTAssertThrowsError(try store.addMedia(item))
        var invalid = item
        invalid.id = UUID()
        invalid.byteCount = -1
        XCTAssertThrowsError(try store.addMedia(invalid))
        var duplicateAudio = report
        duplicateAudio.id = UUID()
        XCTAssertThrowsError(try store.saveReport(duplicateAudio))
        XCTAssertEqual(try Data(contentsOf: files.journalURL), original)
    }

    func testDeletionQueueCannotDeleteRetainedAttachment() throws {
        let files = try files()
        let item = MediaItem(id: UUID(), kind: .photo, createdAt: .now, byteCount: 4)
        let journal = FieldJournal(media: [item], pendingDeletions: AttachmentFile.files(for: item))
        let bytes = try JSONEncoder().encode(journal)
        try SecureFiles.write(bytes, to: files.journalURL)
        let url = files.mediaDirectory.appendingPathComponent(item.fileName)
        try SecureFiles.write(Data("test".utf8), to: url)
        let store = LocalStore(files: files)
        XCTAssertThrowsError(try store.load())
        XCTAssertFalse(store.isLoaded)
        XCTAssertEqual(try Data(contentsOf: files.journalURL), bytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testReplacingAudioCleansOnlyThePreviousAttachment() throws {
        let files = try files()
        let store = LocalStore(files: files)
        try store.load()
        var report = SevenSReport()
        let old = VoiceRecording(id: UUID(), recordedAt: .now, duration: 3, language: "en-US")
        var new = old
        new.id = UUID()
        for audio in [old, new] {
            try SecureFiles.write(Data("test".utf8), to: AttachmentFile.voice(audio).url(in: files))
        }
        report.recording = old
        try store.saveReport(report)
        report.recording = new
        try store.saveReport(report)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: AttachmentFile.voice(old).url(in: files).path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: AttachmentFile.voice(new).url(in: files).path))
        let reopened = LocalStore(files: files)
        try reopened.load()
        XCTAssertEqual(reopened.reports, [report])
    }

    func testAtomicReplacementRetainsBackupExclusion() throws {
        let files = try files()
        for text in ["first", "replacement"] {
            try SecureFiles.write(Data(text.utf8), to: files.journalURL)
            XCTAssertEqual(try Data(contentsOf: files.journalURL), Data(text.utf8))
            XCTAssertEqual(
                try files.journalURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
                    .isExcludedFromBackup, true)
        }
    }

    func testInvalidBoundsReturnFalseInsteadOfFormingInvalidRanges() {
        let point = Coordinate(latitude: 60, longitude: 16)
        XCTAssertFalse(MapBounds(west: 25, south: 55, east: 10, north: 70).contains(point))
        XCTAssertFalse(MapBounds(west: .nan, south: 55, east: 25, north: 70).contains(point))
    }

    func testCleanupFailureIsVisibleAndCanBeRetried() throws {
        let files = try files()
        let item = MediaItem(id: UUID(), kind: .photo, createdAt: .now, byteCount: 4)
        let attachment = AttachmentFile.files(for: item)[0]
        let url = attachment.url(in: files)
        try SecureFiles.write(Data("test".utf8), to: url)
        try SecureFiles.write(
            JSONEncoder().encode(FieldJournal(pendingDeletions: [attachment])), to: files.journalURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: files.mediaDirectory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: files.mediaDirectory.path)
        }
        let store = LocalStore(files: files)
        try store.load()
        XCTAssertTrue(store.isLoaded)
        XCTAssertNotNil(store.cleanupError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let pending = try JSONDecoder().decode(FieldJournal.self, from: Data(contentsOf: files.journalURL))
        XCTAssertEqual(pending.pendingDeletions, [attachment])

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: files.mediaDirectory.path)
        store.retryPendingDeletions()
        XCTAssertNil(store.cleanupError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(
            try JSONDecoder().decode(FieldJournal.self, from: Data(contentsOf: files.journalURL)).pendingDeletions)
    }

    func testUnreadableJournalNeverLoadsAsAnEmptyNotebook() throws {
        let files = try files()
        let original = try JSONEncoder().encode(FieldJournal(callsign: "PRESERVED"))
        try SecureFiles.write(original, to: files.journalURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: files.journalURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: files.journalURL.path)
        }
        let store = LocalStore(files: files)
        XCTAssertThrowsError(try store.load())
        XCTAssertFalse(store.isLoaded)
        XCTAssertThrowsError(try store.setCallsign("REPLACEMENT"))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: files.journalURL.path)
        XCTAssertEqual(try Data(contentsOf: files.journalURL), original)
        try store.load()
        XCTAssertEqual(store.callsign, "PRESERVED")
    }

    func testOversizedJournalIsPreservedWithoutLoading() throws {
        let files = try files()
        try SecureFiles.write(Data(), to: files.journalURL)
        let handle = try FileHandle(forWritingTo: files.journalURL)
        defer { try? handle.close() }
        let size = FieldJournal.maximumBytes + 1
        try handle.truncate(atOffset: UInt64(size))
        let store = LocalStore(files: files)
        XCTAssertThrowsError(try store.load())
        XCTAssertFalse(store.isLoaded)
        XCTAssertThrowsError(try store.setCallsign("REPLACEMENT"))
        XCTAssertEqual(try files.journalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size)
    }
}
