import Foundation
import ImageIO

/// Serial decoding bounds concurrent image allocations and keeps disk reads and
/// decompression off the main actor. Original vault files are never modified.
actor LocalImageLoader {
    static let shared = LocalImageLoader()

    func image(at url: URL, maximumPixelSize: Int) throws -> CGImage {
        try Task.checkCancellation()
        guard url.isFileURL, (1...4096).contains(maximumPixelSize) else { throw AppError.invalidMedia }
        return try autoreleasepool {
            guard
                let source = CGImageSourceCreateWithURL(
                    url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                let image = CGImageSourceCreateThumbnailAtIndex(
                    source, 0,
                    [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                        kCGImageSourceShouldCacheImmediately: true,
                    ] as CFDictionary)
            else { throw AppError.invalidMedia }
            try Task.checkCancellation()
            return image
        }
    }
}
