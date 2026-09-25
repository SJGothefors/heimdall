import Darwin
import Foundation

/// iOS Data Protection is the encryption boundary; no home-grown crypto or keys.
struct SecureFiles: Sendable {
    let root: URL

    init(root: URL? = nil) throws {
        self.root =
            try root
            ?? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true
            ).appendingPathComponent("Heimdall", isDirectory: true)
        try Self.createDirectory(self.root)
        try Self.createDirectory(mediaDirectory)
        try Self.createDirectory(stagingDirectory)
        try Self.createDirectory(voiceDirectory)
    }

    var journalURL: URL { root.appendingPathComponent("journal.json") }
    var voiceDirectory: URL { root.appendingPathComponent("Voice", isDirectory: true) }
    var mediaDirectory: URL { root.appendingPathComponent("Media", isDirectory: true) }
    var stagingDirectory: URL { root.appendingPathComponent("Staging", isDirectory: true) }
    var importedMapDirectory: URL { root.appendingPathComponent("ImportedMap", isDirectory: true) }

    static func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        try protect(url)
    }

    static func protect(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutable.setResourceValues(values)
    }

    static func write(_ data: Data, to url: URL) throws {
        // Configure the replacement before publishing it. Nothing may throw
        // after rename succeeds, or the caller could roll back a committed save.
        let staged = url.deletingLastPathComponent().appendingPathComponent(
            ".write-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staged) }
        try data.write(to: staged, options: [.completeFileProtection])
        try protect(staged)
        let handle = try FileHandle(forWritingTo: staged)
        defer { try? handle.close() }
        try handle.synchronize()
        guard rename(staged.path, url.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    func cleanStaging() throws {
        for url in try FileManager.default.contentsOfDirectory(
            at: stagingDirectory, includingPropertiesForKeys: nil)
        {
            try FileManager.default.removeItem(at: url)
        }
    }
}
