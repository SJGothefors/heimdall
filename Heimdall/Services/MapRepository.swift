import Foundation
import UIKit
import ImageIO
import Observation

struct LoadedMap: Sendable {
    let package: MapPackage
    let photo: Data
}

@MainActor @Observable
final class MapRepository {
    private(set) var package: MapPackage?
    private(set) var photo: UIImage?
    private(set) var isImported = false
    private(set) var isLoading = false
    private(set) var revision = UUID()
    let files: SecureFiles

    init(files: SecureFiles) { self.files = files }

    func load() async throws {
        guard package == nil else { return }
        let imported = FileManager.default.fileExists(atPath: files.importedMapDirectory.path)
        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("Sweden") else { throw AppError.missingMap }
        let directory = imported ? files.importedMapDirectory : bundled
        let loaded = try await Task.detached(priority: .userInitiated) { try Self.read(directory) }.value
        apply(loaded, imported: imported)
    }

    func importDirectory(_ source: URL) async throws {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let files = files
        let loaded = try await Task.detached(priority: .userInitiated) {
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            let loaded = try Self.read(source)
            let stage = files.root.appendingPathComponent("Map-\(UUID().uuidString)", isDirectory: true)
            try SecureFiles.createDirectory(stage)
            defer { try? FileManager.default.removeItem(at: stage) }
            try SecureFiles.write(JSONEncoder().encode(loaded.package), to: stage.appendingPathComponent("map.json"))
            try SecureFiles.write(loaded.photo, to: stage.appendingPathComponent("photo.jpg"))
            if FileManager.default.fileExists(atPath: files.importedMapDirectory.path) {
                _ = try FileManager.default.replaceItemAt(files.importedMapDirectory, withItemAt: stage)
            } else {
                try FileManager.default.moveItem(at: stage, to: files.importedMapDirectory)
            }
            return loaded
        }.value
        apply(loaded, imported: true)
    }

    func useBundledMap() async throws {
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Sweden") else { throw AppError.missingMap }
        let loaded = try await Task.detached { try Self.read(directory) }.value
        if FileManager.default.fileExists(atPath: files.importedMapDirectory.path) {
            try FileManager.default.removeItem(at: files.importedMapDirectory)
        }
        apply(loaded, imported: false)
    }

    private func apply(_ loaded: LoadedMap, imported: Bool) {
        package = loaded.package
        photo = UIImage(data: loaded.photo)
        isImported = imported
        revision = UUID()
    }

    nonisolated static func read(_ directory: URL) throws -> LoadedMap {
        let directoryValues = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard directoryValues.isDirectory == true, directoryValues.isSymbolicLink != true else { throw AppError.invalidMap }
        func readFile(_ name: String, limit: Int) throws -> Data {
            let url = directory.appendingPathComponent(name)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size > 0, size <= limit else { throw AppError.invalidMap }
            return try Data(contentsOf: url)
        }
        let map = try readFile("map.json", limit: 40_000_000)
        let package = try JSONDecoder().decode(MapPackage.self, from: map)
        try package.validate()
        let photo = try readFile("photo.jpg", limit: 32_000_000)
        guard let image = CGImageSourceCreateWithData(photo as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 24_000_000,
              CGImageSourceCreateImageAtIndex(image, 0, nil) != nil else { throw AppError.invalidMap }
        return LoadedMap(package: package, photo: photo)
    }
}
