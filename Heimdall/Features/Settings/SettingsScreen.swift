import SwiftUI
import UniformTypeIdentifiers

struct SettingsScreen: View {
    @Environment(AppNavigation.self) private var navigation
    let store: LocalStore
    let maps: MapRepository
    let location: LocationService
    let security: DeviceSecurity
    @State private var importing = false
    @State private var error: String?
    @State private var deletePack: RegionPack?
    @State private var speechStatus: [String: String] = [:]
    @State private var preparingLanguage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(maps.regions) { pack in regionRow(pack) }
                    Button("Import map package", systemImage: "square.and.arrow.down") { importing = true }.disabled(
                        maps.isLoading)
                    if maps.isLoading { ProgressView("Validating and unpacking…") }
                    NavigationLink("Map credits & coverage") { MapCredits(maps: maps) }
                } header: {
                    Text("Offline map regions")
                } footer: {
                    Text(
                        "Load up to two regions together. Sweden stays available outside them. Archive removes the working copy and keeps the stored package."
                    )
                }
                Section {
                    Toggle(
                        "Use GPS",
                        isOn: Binding(
                            get: { location.isEnabled }, set: { if $0 { location.enable() } else { location.stop() } }))
                    if let position = location.currentPosition {
                        Text(position.coordinate.formatted).font(.system(.body, design: .monospaced))
                        Text(
                            "\(position.source.rawValue.uppercased()) · \(position.timestamp.formatted(date: .abbreviated, time: .shortened))"
                        ).font(.caption).foregroundStyle(Theme.muted)
                    }
                    Button("Set position on map", systemImage: "mappin.and.ellipse") {
                        navigation.section = .map
                        navigation.selectingPosition = true
                    }
                    if store.ownPosition != nil {
                        Button("Clear manual position") {
                            do {
                                try store.setOwnPosition(nil)
                                location.manualPosition = nil
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                } header: {
                    Text("My position")
                } footer: {
                    Text(
                        "GPS is off by default and stops when the app locks. Manual positions are saved until changed. Voice reports retain a snapshot of the position and its age at recording time."
                    )
                }
                Section {
                    ForEach(["sv-SE", "en-US"], id: \.self) { language in
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent(
                                language == "sv-SE" ? "Svenska" : "English",
                                value: speechStatus[language] ?? "Checking…")
                            Button(
                                preparingLanguage == language ? "Preparing…" : "Prepare language (internet required)"
                            ) {
                                preparingLanguage = language
                                Task {
                                    defer { preparingLanguage = nil }
                                    do { try await LocalSpeech.prepare(language) } catch {
                                        self.error = error.localizedDescription
                                    }
                                    speechStatus[language] = await LocalSpeech.status(language)
                                }
                            }.disabled(
                                preparingLanguage != nil || speechStatus[language] == "Ready offline"
                                    || speechStatus[language] == "Not supported on this device")
                        }
                    }
                } header: {
                    Text("Offline speech")
                } footer: {
                    Text(
                        "Download Apple's language models before going offline. Audio and transcription stay on this iPhone. Recording and manual notes work without a model."
                    )
                }
                Section("Protection") {
                    Button("Lock now", systemImage: "lock") {
                        location.stop()
                        security.lock()
                    }
                    Text("Device authentication · protected local storage · no backups").font(.caption).foregroundStyle(
                        Theme.muted)
                    Text("Deleting the app removes reports and media. iOS screenshots cannot be prevented.").font(
                        .caption
                    ).foregroundStyle(Theme.muted)
                }
            }.scrollContentBackground(.hidden).background(Theme.background)
                .navigationTitle("Device").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { AppMenu() } }
                .task {
                    for language in ["sv-SE", "en-US"] { speechStatus[language] = await LocalSpeech.status(language) }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.zip]) { result in
                    switch result {
                    case .success(let url):
                        Task {
                            do { try await maps.importRegion(url) } catch { self.error = error.localizedDescription }
                        }
                    case .failure(let error): self.error = error.localizedDescription
                    }
                }
                .alert("Device", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK", role: .cancel) { error = nil }
                } message: {
                    Text(error ?? "")
                }
                .confirmationDialog(
                    "Remove this stored map package?",
                    isPresented: Binding(get: { deletePack != nil }, set: { if !$0 { deletePack = nil } }),
                    titleVisibility: .visible
                ) {
                    Button("Remove package", role: .destructive) {
                        if let pack = deletePack {
                            do { try maps.deleteRegion(pack) } catch { self.error = error.localizedDescription }
                        }
                        deletePack = nil
                    }
                }
        }
    }

    private func regionRow(_ pack: RegionPack) -> some View {
        let sizeLabel = ByteCountFormatter.string(fromByteCount: pack.byteCount, countStyle: .file)
        let dateLabel = String(pack.manifest.sourceDate.prefix(10))
        return
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(pack.manifest.name).font(.headline)
                    Spacer()
                    Text(maps.isLoaded(pack) ? "Loaded" : "Stored ZIP").font(.caption).foregroundStyle(Theme.muted)
                }
                Text(sizeLabel + " · " + dateLabel)
                    .font(.caption).foregroundStyle(Theme.muted)
                HStack {
                    if maps.isLoaded(pack) {
                        Button("Show map", systemImage: "map") {
                            maps.focus(on: pack.manifest)
                            navigation.section = .map
                        }
                        Spacer()
                        Button("Archive", systemImage: "archivebox") {
                            do { try maps.archiveRegion(pack.manifest) } catch {
                                self.error = error.localizedDescription
                            }
                        }.accessibilityIdentifier("archive-" + pack.id)
                    } else {
                        Button("Load region", systemImage: "shippingbox") {
                            Task {
                                do {
                                    try await maps.loadRegion(pack)
                                    navigation.section = .map
                                } catch { self.error = error.localizedDescription }
                            }
                        }.accessibilityIdentifier("load-" + pack.id).disabled(maps.loadedRegions.count >= 2)
                        Spacer()
                        if !pack.bundled { Button("Remove", role: .destructive) { deletePack = pack } }
                    }
                }.buttonStyle(.borderless).frame(minHeight: 44)
            }.padding(.vertical, 4).disabled(maps.isLoading)
    }

}
