import CryptoKit
import Foundation
import ZIPFoundation

/// Packages contain data only. Styles, glyphs and all resource URLs are owned by
/// the app, so a package cannot inject a network source or executable content.
nonisolated enum RegionPacks {
    static let maximumBytes: UInt64 = 2_000_000_000
    static let names = Set(["manifest.json", "basemap.pmtiles", "imagery.pmtiles"])

    static func manifest(in archive: Archive) throws -> RegionManifest {
        var paths = Set<String>()
        var total: UInt64 = 0
        for entry in archive {
            guard paths.count < 3, names.contains(entry.path), paths.insert(entry.path).inserted,
                entry.type == .file, entry.uncompressedSize > 0, entry.uncompressedSize <= maximumBytes
            else { throw AppError.invalidMap }
            total += entry.uncompressedSize
            guard total <= maximumBytes else { throw AppError.invalidMap }
        }
        guard paths.contains("manifest.json"), paths.contains("basemap.pmtiles"),
            let entry = archive["manifest.json"], entry.uncompressedSize <= 16_384
        else { throw AppError.invalidMap }
        var data = Data()
        let checksum = try archive.extract(entry) { chunk in
            guard data.count + chunk.count <= 16_384 else { throw AppError.invalidMap }
            data.append(chunk)
        }
        guard checksum == entry.checksum else { throw AppError.invalidMap }
        let manifest = try JSONDecoder().decode(RegionManifest.self, from: data)
        try manifest.validate()
        guard paths.contains("imagery.pmtiles") == (manifest.imagerySHA256 != nil) else { throw AppError.invalidMap }
        return manifest
    }

    static func inspect(_ url: URL, bundled: Bool = false) throws -> RegionPack {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
            let bytes = values.fileSize, bytes > 0, bytes <= maximumBytes
        else { throw AppError.invalidMap }
        let archive = try Archive(url: url, accessMode: .read)
        return RegionPack(
            manifest: try manifest(in: archive), archiveURL: url, byteCount: Int64(bytes), bundled: bundled)
    }

    static func extract(_ url: URL, to directory: URL) throws -> RegionManifest {
        _ = try inspect(url)
        let archive = try Archive(url: url, accessMode: .read)
        let manifest = try manifest(in: archive)
        try SecureFiles.createDirectory(directory)
        var success = false
        defer { if !success { try? FileManager.default.removeItem(at: directory) } }
        for entry in archive {
            let target = directory.appendingPathComponent(entry.path)
            guard
                FileManager.default.createFile(
                    atPath: target.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete])
            else { throw AppError.invalidMap }
            let handle = try FileHandle(forWritingTo: target)
            defer { try? handle.close() }
            var written: UInt64 = 0
            var hash = SHA256()
            let crc = try archive.extract(entry, bufferSize: 65_536) { data in
                written += UInt64(data.count)
                guard written <= entry.uncompressedSize, written <= maximumBytes else { throw AppError.invalidMap }
                try handle.write(contentsOf: data)
                hash.update(data: data)
            }
            guard crc == entry.checksum, written == entry.uncompressedSize else { throw AppError.invalidMap }
            try SecureFiles.protect(target)
            if entry.path.hasSuffix(".pmtiles") {
                let expected = entry.path == "basemap.pmtiles" ? manifest.sha256 : manifest.imagerySHA256
                guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == expected else {
                    throw AppError.invalidMap
                }
                try validatePMTiles(target, vector: entry.path == "basemap.pmtiles")
            }
        }
        success = true
        return manifest
    }

    /// Bound the compressed copy as well as extraction. Validation happens on
    /// this snapshot, never on a provider file that is later copied again.
    static func copyArchive(_ source: URL, to destination: URL) throws {
        let pack = try inspect(source)
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard FileManager.default.createFile(
            atPath: destination.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete])
        else { throw AppError.invalidMap }
        try SecureFiles.protect(destination)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var copied: Int64 = 0
        while let chunk = try input.read(upToCount: 65_536), !chunk.isEmpty {
            copied += Int64(chunk.count)
            guard copied <= pack.byteCount else { throw AppError.invalidMap }
            try output.write(contentsOf: chunk)
        }
        guard copied == pack.byteCount else { throw AppError.invalidMap }
        try output.synchronize()
    }

    static func validatePMTiles(_ url: URL, vector: Bool) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let size = try file.seekToEnd()
        try file.seek(toOffset: 0)
        guard let header = try file.read(upToCount: 127), header.count == 127,
            String(data: header.prefix(7), encoding: .ascii) == "PMTiles", header[7] == 3,
            vector ? header[99] == 1 : (2...4).contains(header[99]),
            header[100] <= header[101], header[101] <= 18
        else { throw AppError.invalidMap }
        func uint64(_ offset: Int) -> UInt64 {
            (0..<8).reduce(0) { $0 | UInt64(header[offset + $1]) << ($1 * 8) }
        }
        for offset in [8, 24, 40, 56] {
            let start = uint64(offset)
            let length = uint64(offset + 8)
            guard start <= size, length <= size - start else { throw AppError.invalidMap }
        }
    }
}
