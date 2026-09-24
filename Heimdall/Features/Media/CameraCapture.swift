import SwiftUI
import UniformTypeIdentifiers

enum CaptureResult { case photo(Data), video(URL), failure(String), cancelled }

struct CameraCapture: UIViewControllerRepresentable {
    let video: Bool
    let completion: (CaptureResult) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [video ? UTType.movie.identifier : UTType.image.identifier]
        picker.cameraCaptureMode = video ? .video : .photo
        picker.videoQuality = .typeHigh
        picker.videoMaximumDuration = 300
        picker.cameraFlashMode = .off
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (CaptureResult) -> Void
        init(completion: @escaping (CaptureResult) -> Void) { self.completion = completion }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(.cancelled) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL { completion(.video(url)); return }
            guard let original = info[.originalImage] as? UIImage else { completion(.failure(AppError.invalidMedia.localizedDescription)); return }
            // Redraw pixel content to normalize orientation and discard EXIF/GPS metadata.
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let pixels = CGSize(width: original.size.width * original.scale, height: original.size.height * original.scale)
            let renderer = UIGraphicsImageRenderer(size: pixels, format: format)
            let clean = renderer.image { _ in original.draw(in: CGRect(origin: .zero, size: pixels)) }
            guard let data = clean.jpegData(compressionQuality: 0.9) else { completion(.failure(AppError.invalidMedia.localizedDescription)); return }
            completion(.photo(data))
        }
    }
}
