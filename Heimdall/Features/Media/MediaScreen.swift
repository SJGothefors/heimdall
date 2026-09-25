import SwiftUI
import AVKit

struct MediaScreen: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let store: LocalStore
    @State private var capture: CaptureMode?
    @State private var selected: MediaItem?
    @State private var saving = false
    @State private var requesting = false
    @State private var error: String?
    enum CaptureMode: String, Identifiable { case photo, video; var id: String { rawValue } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Label("ON THIS IPHONE", systemImage: "internaldrive")
                        Spacer()
                        Text("\(store.media.count) FILES")
                    }.font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Theme.muted)
                    HStack(spacing: 12) {
                        captureButton("Take photo", symbol: "camera", mode: .photo)
                        captureButton("Record video", symbol: "video", mode: .video)
                    }.disabled(saving || requesting)
                    if saving { HStack { ProgressView(); Text("Saving to protected storage…").font(.caption) } }
                    if store.media.isEmpty {
                        if verticalSizeClass == .compact {
                            Text("Photos and videos stay in Heimdall. Nothing is uploaded or added to your Photos library.")
                                .font(.caption).foregroundStyle(Theme.muted)
                        } else {
                            ContentUnavailableView("A local record", systemImage: "photo.on.rectangle.angled",
                                description: Text("Photos and videos stay in Heimdall. Nothing is uploaded or added to your Photos library."))
                                .padding(.top, 35)
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 240))], spacing: 12) {
                            ForEach(store.media) { item in
                                Button { selected = item } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ZStack(alignment: .bottomTrailing) {
                                            LocalThumbnail(url: store.files.mediaDirectory.appendingPathComponent(item.thumbnailName))
                                                .frame(height: 160).frame(maxWidth: .infinity).clipped()
                                            Image(systemName: item.kind == .photo ? "camera.fill" : "play.fill")
                                                .font(.caption).padding(9).background(.black.opacity(0.6), in: Circle()).padding(8)
                                        }.clipShape(RoundedRectangle(cornerRadius: 16))
                                        Text(item.createdAt, format: .dateTime.day().month().hour().minute())
                                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
                                    }
                                }.buttonStyle(.plain).accessibilityLabel("\(item.kind.rawValue), \(item.createdAt.formatted())")
                            }
                        }
                    }
                }.padding(22)
            }.background(Theme.background).navigationTitle("Media").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { AppMenu() } }
                .fullScreenCover(item: $capture) { mode in
                    CameraCapture(video: mode == .video) { result in
                        capture = nil
                        Task { await save(result) }
                    }.ignoresSafeArea()
                }
                .sheet(item: $selected) { item in MediaDetail(item: item, store: store) }
                .alert("Camera & storage", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK", role: .cancel) { error = nil }
                } message: { Text(error ?? "") }
        }
    }

    private func captureButton(_ title: String, symbol: String, mode: CaptureMode) -> some View {
        Button { Task { await requestCapture(mode) } } label: {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(Theme.accent)
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(19)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.line))
        }
    }

    private func requestCapture(_ mode: CaptureMode) async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { error = AppError.cameraUnavailable.localizedDescription; return }
        requesting = true
        defer { requesting = false }
        guard await AVCaptureDevice.requestAccess(for: .video) else { error = "Allow camera access in iPhone Settings to capture media."; return }
        if mode == .video {
            guard await AVCaptureDevice.requestAccess(for: .audio) else { error = "Allow microphone access in iPhone Settings to record video with audio."; return }
        }
        capture = mode
    }

    private func save(_ result: CaptureResult) async {
        if case .cancelled = result { return }
        if case .failure(let message) = result { error = message; return }
        saving = true
        defer { saving = false }
        let vault = MediaVault(files: store.files)
        do {
            let item: MediaItem
            switch result {
            case .photo(let data): item = try await vault.savePhoto(data)
            case .video(let url): item = try await vault.saveVideo(url)
            default: return
            }
            do { try store.addMedia(item) }
            catch { await vault.discard(item); throw error }
        } catch { self.error = "Media was not saved. \(error.localizedDescription)" }
    }
}

struct LocalThumbnail: View {
    let url: URL
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Rectangle().fill(Theme.panel).overlay { Image(systemName: "photo").foregroundStyle(Theme.muted) } }
        }.task(id: url) { image = UIImage(contentsOfFile: url.path) }
    }
}

struct MediaDetail: View {
    let item: MediaItem
    let store: LocalStore
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var confirmDelete = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if item.kind == .video {
                    VideoPlayer(player: player).onAppear { player = AVPlayer(url: url) }.onDisappear { player?.pause(); player = nil }
                } else if let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else { ContentUnavailableView("File unavailable", systemImage: "photo.badge.exclamationmark") }
                Text(item.createdAt, format: .dateTime.day().month().year().hour().minute()).font(.caption).foregroundStyle(Theme.muted)
                Text(ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)).font(.caption).foregroundStyle(Theme.muted)
                Button("Delete from device", role: .destructive) { confirmDelete = true }.padding(.bottom)
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background)
                .navigationTitle(item.kind == .photo ? "Photo" : "Video").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .confirmationDialog("Delete this file?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        do { player?.pause(); try store.deleteMedia(item); dismiss() } catch { self.error = error.localizedDescription }
                    }
                } message: { Text("This cannot be undone.") }
        }
    }
    private var url: URL { store.files.mediaDirectory.appendingPathComponent(item.fileName) }
}
