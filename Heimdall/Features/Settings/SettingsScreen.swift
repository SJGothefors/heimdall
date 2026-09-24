import SwiftUI
import UniformTypeIdentifiers

struct SettingsScreen: View {
    let store: LocalStore
    let maps: MapRepository
    let location: LocationService
    let security: DeviceSecurity
    @State private var importing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "shield.lefthalf.filled").font(.system(size: 32)).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Heimdall").font(.title2.weight(.semibold))
                            Text("Offline by design").font(.caption).foregroundStyle(Theme.muted)
                        }
                    }.padding(.vertical, 8)
                    Label("No accounts, tracking or cloud sync", systemImage: "network.slash")
                        .font(.subheadline)
                }
                Section("Maps on this iPhone") {
                    LabeledContent("Active map", value: maps.package?.name ?? "Loading")
                    Text(maps.package?.detail ?? "").font(.caption).foregroundStyle(Theme.muted)
                    Button("Import local map folder", systemImage: "folder.badge.plus") { importing = true }.disabled(maps.isLoading)
                    if maps.isLoading { ProgressView("Validating and importing…") }
                    if maps.isImported {
                        Button("Use bundled Sweden overview") {
                            Task { do { try await maps.useBundledMap() } catch { self.error = error.localizedDescription } }
                        }.disabled(maps.isLoading)
                    }
                    NavigationLink("Map coverage & credits") { mapInformation }
                }
                Section("Location") {
                    Toggle("Use location while open", isOn: Binding(get: { location.isEnabled }, set: { if $0 { location.enable() } else { location.stop() } }))
                    Text("Location stops when the app locks or goes into the background. No location history is saved.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Section("Local protection") {
                    Label("Device authentication required", systemImage: "faceid")
                    Label("Files protected while iPhone is locked", systemImage: "lock.doc")
                    Label("App data excluded from backups", systemImage: "icloud.slash")
                    Button("Lock now", systemImage: "lock") { location.stop(); security.lock() }
                }
                Section {
                    Text("Media stays in the app, separate from Photos. Deleting the app removes your local journal and media. No recovery or sync service is provided.")
                    Text("Screen recording and mirroring hide the interface. iOS screenshots cannot be prevented. This build has not been independently security audited or certified for operational use.")
                } header: { Text("Device awareness") }
                    .font(.caption).foregroundStyle(Theme.muted)
            }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("Device")
                .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
                    switch result {
                    case .success(let url):
                        Task { do { try await maps.importDirectory(url) } catch { self.error = error.localizedDescription } }
                    case .failure(let error): self.error = error.localizedDescription
                    }
                }
                .alert("Map import", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK", role: .cancel) { error = nil }
                } message: { Text(error ?? "") }
        }
    }

    private var mapInformation: some View {
        List {
            Section("Bundled Sweden overview") {
                Text("The included map covers 55–70° N, 10–25° E. Vector features are Natural Earth 1:10 million geography, major roads and settlements. This is an overview, not detailed field cartography.")
                Text("Photo mode uses a NASA Blue Marble satellite mosaic from July 2004. It is low resolution and is not current aerial photography.")
                Text("The 3D view uses sampled Mapzen elevation data. Heights are exaggerated 12×; it is not a line-of-sight or navigation tool. Edit annotations in Vector or Photo mode.")
            }
            Section("Import a detailed local map") {
                Text("Select a folder containing map.json and photo.jpg. Use the documented Heimdall map-pack format. All files are validated, copied into local storage and excluded from backups. Imported packs may cover a smaller area within Sweden.")
                Text("Use a folder already downloaded under On My iPhone. A cloud file provider may need a connection to make its files available.")
            }
            Section("Active data attribution") { Text(maps.package?.attribution ?? "") }
            Section("Bundled data credits") {
                Text("Natural Earth: public domain. NASA Blue Marble: NASA Earth Observatory. Terrain: Mapzen / Tilezen; global GMTED2010 and SRTM courtesy of USGS; ETOPO1 courtesy of NOAA; Europe terrain produced using Copernicus data and information funded by the European Union, EU-DEM layers; Norway terrain © Kartverket. ArcticDEM DEMs were created from DigitalGlobe imagery and funded under NSF awards 1043681, 1559691 and 1542736.")
            }
        }.font(.subheadline).scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("Map information").navigationBarTitleDisplayMode(.inline)
    }
}
