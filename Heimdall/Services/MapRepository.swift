import Foundation
import ImageIO
import Observation
import UIKit

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
    private(set) var regions: [RegionPack] = []
    private(set) var loadedRegions: [RegionManifest] = []
    private(set) var regionFocus: Coordinate?
    private var loadedRegionsURL: URL { files.root.appendingPathComponent("LoadedRegions", isDirectory: true) }
    func directory(for region: RegionManifest) -> URL {
        loadedRegionsURL.appendingPathComponent(region.id, isDirectory: true)
    }
    func isLoaded(_ pack: RegionPack) -> Bool { loadedRegions.contains { $0.id == pack.id } }

    enum RegionError: LocalizedError {
        case capacityReached
        var errorDescription: String? { "Two regions are already loaded. Archive one before loading another." }
    }
    var archivesURL: URL { files.root.appendingPathComponent("MapPacks", isDirectory: true) }
    let files: SecureFiles

    init(files: SecureFiles) { self.files = files }

    func load() async throws {
        guard package == nil else { return }
        let imported = FileManager.default.fileExists(atPath: files.importedMapDirectory.path)
        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("Sweden") else { throw AppError.missingMap }
        let directory = imported ? files.importedMapDirectory : bundled
        let loaded = try await Task.detached(priority: .userInitiated) { try Self.read(directory) }.value
        try refreshRegions()
        try SecureFiles.createDirectory(loadedRegionsURL)
        let directories = try FileManager.default.contentsOfDirectory(
            at: loadedRegionsURL, includingPropertiesForKeys: nil)
        loadedRegions = try directories.map { directory in
            let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
            let manifest = try JSONDecoder().decode(RegionManifest.self, from: data)
            try manifest.validate()
            guard directory.lastPathComponent == manifest.id else { throw AppError.invalidMap }
            try RegionPacks.validatePMTiles(directory.appendingPathComponent("basemap.pmtiles"), vector: true)
            if manifest.imagerySHA256 != nil {
                try RegionPacks.validatePMTiles(directory.appendingPathComponent("imagery.pmtiles"), vector: false)
            }
            return manifest
        }.sorted { $0.id < $1.id }
        guard loadedRegions.count <= 2 else { throw AppError.invalidMap }
        regionFocus = loadedRegions.first?.focus
        let configured = files.root.appendingPathComponent("RegionSetupComplete")
        if !FileManager.default.fileExists(atPath: configured.path) {
            if loadedRegions.isEmpty, let gotland = regions.first(where: { $0.id == "gotland" }) {
                try await loadRegion(gotland)
            }
            try SecureFiles.write(Data("1".utf8), to: configured)
        }
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
            let stage = files.stagingDirectory.appendingPathComponent("Map-\(UUID().uuidString)", isDirectory: true)
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
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Sweden") else {
            throw AppError.missingMap
        }
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

    func refreshRegions() throws {
        try SecureFiles.createDirectory(archivesURL)
        var found: [RegionPack] = []
        if let bundle = Bundle.main.resourceURL?.appendingPathComponent("Maps") {
            for url in try FileManager.default.contentsOfDirectory(at: bundle, includingPropertiesForKeys: nil)
            where url.pathExtension == "zip" {
                found.append(try RegionPacks.inspect(url, bundled: true))
            }
        }
        for url in try FileManager.default.contentsOfDirectory(at: archivesURL, includingPropertiesForKeys: nil)
        where url.pathExtension == "zip" {
            let pack = try RegionPacks.inspect(url)
            found.removeAll { $0.id == pack.id }
            found.append(pack)
        }
        regions = found.sorted { $0.manifest.name < $1.manifest.name }
    }

    func importRegion(_ source: URL) async throws {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let root = files.stagingDirectory
        let archives = archivesURL
        try await Task.detached(priority: .userInitiated) {
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            // Validate a private snapshot, then keep those exact bytes. A file
            // provider can change the selected file while an import is running.
            let copy = root.appendingPathComponent("Archive-\(UUID().uuidString).zip")
            defer { try? FileManager.default.removeItem(at: copy) }
            try RegionPacks.copyArchive(source, to: copy)
            let stage = root.appendingPathComponent("RegionImport-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: stage) }
            let manifest = try RegionPacks.extract(copy, to: stage)
            let destination = archives.appendingPathComponent(manifest.id + ".zip")
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: copy)
            } else {
                try FileManager.default.moveItem(at: copy, to: destination)
            }
        }.value
        try refreshRegions()
    }

    func loadRegion(_ pack: RegionPack) async throws {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard isLoaded(pack) || loadedRegions.count < 2 else { throw RegionError.capacityReached }
        let destination = directory(for: pack.manifest)
        let root = files.stagingDirectory
        let manifest = try await Task.detached(priority: .userInitiated) {
            let stage = root.appendingPathComponent("RegionStage-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: stage) }
            let manifest = try RegionPacks.extract(pack.archiveURL, to: stage)
            guard manifest == pack.manifest else { throw AppError.invalidMap }
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: stage)
            } else {
                try FileManager.default.moveItem(at: stage, to: destination)
            }
            return manifest
        }.value
        loadedRegions.removeAll { $0.id == manifest.id }
        loadedRegions.append(manifest)
        loadedRegions.sort { $0.id < $1.id }
        regionFocus = manifest.focus
        revision = UUID()
    }

    func archiveRegion(_ region: RegionManifest) throws {
        guard !isLoading else { return }
        // Keep the compressed original; remove only the expanded working copy.
        let url = directory(for: region)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        loadedRegions.removeAll { $0.id == region.id }
        revision = UUID()
    }

    func focus(on region: RegionManifest) { regionFocus = region.focus }

    func deleteRegion(_ pack: RegionPack) throws {
        guard !pack.bundled, !isLoading else { return }
        if isLoaded(pack) { try archiveRegion(pack.manifest) }
        try FileManager.default.removeItem(at: pack.archiveURL)
        try refreshRegions()
    }

    nonisolated static func read(_ directory: URL) throws -> LoadedMap {
        let directoryValues = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard directoryValues.isDirectory == true, directoryValues.isSymbolicLink != true else {
            throw AppError.invalidMap
        }
        func readFile(_ name: String, limit: Int) throws -> Data {
            let url = directory.appendingPathComponent(name)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                let size = values.fileSize, size > 0, size <= limit
            else { throw AppError.invalidMap }
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
            CGImageSourceCreateImageAtIndex(image, 0, nil) != nil
        else { throw AppError.invalidMap }
        return LoadedMap(package: package, photo: photo)
    }
}
