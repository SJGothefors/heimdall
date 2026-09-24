import AVFoundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

actor MediaVault {
    let files: SecureFiles
    init(files: SecureFiles) { self.files = files }

    func savePhoto(_ jpeg: Data) throws -> MediaItem {
        let item = MediaItem(id: UUID(), kind: .photo, createdAt: Date(), byteCount: Int64(jpeg.count))
        let destination = files.mediaDirectory.appendingPathComponent(item.fileName)
        let thumbnailURL = files.mediaDirectory.appendingPathComponent(item.thumbnailName)
        do {
            try SecureFiles.write(jpeg, to: destination)
            try SecureFiles.write(Self.thumbnail(jpeg), to: thumbnailURL)
            return item
        } catch {
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.removeItem(at: thumbnailURL)
            throw error
        }
    }

    func saveVideo(_ source: URL) async throws -> MediaItem {
        let id = UUID()
        let staging = files.stagingDirectory.appendingPathComponent(id.uuidString + ".mov")
        let destination = files.mediaDirectory.appendingPathComponent(id.uuidString + ".mov")
        let thumbnailURL = files.mediaDirectory.appendingPathComponent(id.uuidString + "-thumb.jpg")
        defer { try? FileManager.default.removeItem(at: staging); try? FileManager.default.removeItem(at: source) }
        do {
            try SecureFiles.protect(source)
            let asset = AVURLAsset(url: source)
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { throw AppError.invalidMedia }
            exporter.metadata = []
            exporter.directoryForTemporaryFiles = files.stagingDirectory
            try await exporter.export(to: staging, as: .mov)
            try SecureFiles.protect(staging)
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: staging))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 500, height: 500)
            let (image, _) = try await generator.image(at: .zero)
            let thumb = try Self.jpeg(image)
            try SecureFiles.write(thumb, to: thumbnailURL)
            try FileManager.default.moveItem(at: staging, to: destination)
            try SecureFiles.protect(destination)
            let bytes = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            return MediaItem(id: id, kind: .video, createdAt: Date(), byteCount: Int64(bytes))
        } catch {
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.removeItem(at: thumbnailURL)
            throw error
        }
    }

    func discard(_ item: MediaItem) {
        try? FileManager.default.removeItem(at: files.mediaDirectory.appendingPathComponent(item.fileName))
        try? FileManager.default.removeItem(at: files.mediaDirectory.appendingPathComponent(item.thumbnailName))
    }

    private static func thumbnail(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 500,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { throw AppError.invalidMedia }
        return try jpeg(image)
    }

    private static func jpeg(_ image: CGImage) throws -> Data {
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.jpeg.identifier as CFString, 1, nil) else { throw AppError.invalidMedia }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw AppError.invalidMedia }
        return result as Data
    }
}
