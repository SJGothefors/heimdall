import Foundation

enum AppError: LocalizedError {
    case invalidMap, invalidState, missingMap, cameraUnavailable, invalidMedia
    case journalFull, attachmentCleanupPending

    var errorDescription: String? {
        switch self {
        case .invalidMap:
            "This map pack is invalid or exceeds the supported limits. Your existing map has not changed."
        case .invalidState:
            "The journal or requested change is invalid. Existing saved records have been preserved."
        case .missingMap:
            "The bundled Sweden map is missing. Install a complete application build without deleting your app data."
        case .cameraUnavailable:
            "A camera is not available on this device. Use a physical iPhone to capture media."
        case .invalidMedia:
            "The captured media could not be saved. Check available storage and try again."
        case .journalFull: "The notebook has reached its size limit. This change was not saved."
        case .attachmentCleanupPending:
            "The notebook was updated, but file cleanup is unfinished. Some deleted attachments may remain on this phone. Retry in Device settings."
        }
    }
}
