import SwiftUI

@main
struct HeimdallApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup { AppRoot().preferredColorScheme(.dark).tint(Theme.accent) }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, shouldAllowExtensionPointIdentifier identifier: UIApplication.ExtensionPointIdentifier) -> Bool {
        identifier != .keyboard
    }
}

struct AppRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isSceneCaptured) private var isCaptured
    @State private var security = DeviceSecurity()
    @State private var store: LocalStore?
    @State private var maps: MapRepository?
    @State private var location = LocationService()
    @State private var error: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if security.isUnlocked, let store, let maps, error == nil {
                MainView(store: store, maps: maps, location: location, security: security)
            } else if let error {
                ContentUnavailableView {
                    Label("Local data unavailable", systemImage: "lock.trianglebadge.exclamationmark")
                } description: { Text(error) } actions: {
                    Button("Try again") { self.error = nil; Task { await prepare() } }
                    if store?.isLoaded == true, maps?.package == nil {
                        Button("Restore bundled map") {
                            Task {
                                do { try await maps?.useBundledMap(); self.error = nil }
                                catch { self.error = error.localizedDescription }
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 24) {
                    Image(systemName: "shield.lefthalf.filled").font(.system(size: 46)).foregroundStyle(Theme.accent)
                    VStack(spacing: 8) {
                        Text("HEIMDALL").font(.system(size: 27, weight: .semibold)).tracking(5)
                        Text("Your field. Your device.").foregroundStyle(Theme.muted)
                    }
                    Button {
                        Task { await security.unlock(); await prepare() }
                    } label: {
                        Label("Unlock Heimdall", systemImage: "faceid").padding(.horizontal, 18).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent).disabled(security.isAuthenticating)
                    if let message = security.message { Text(message).font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center) }
                    Label("Stored only on this iPhone", systemImage: "internaldrive").font(.caption).foregroundStyle(Theme.muted)
                }.padding(36)
            }
            if scenePhase != .active || isCaptured {
                Theme.background.ignoresSafeArea().overlay {
                    VStack(spacing: 16) {
                        Image(systemName: "shield.lefthalf.filled").font(.largeTitle).foregroundStyle(Theme.accent)
                        Text(isCaptured ? "Screen capture is active" : "HEIMDALL").font(.headline)
                        if isCaptured { Text("Stop recording or mirroring to view your data.").font(.footnote).foregroundStyle(Theme.muted) }
                    }
                }.zIndex(100)
            }
        }
        .background(PrivacyShield(visible: scenePhase != .active || isCaptured))
        .task { await security.unlock(); await prepare() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { security.lock(); location.stop() }
        }
        .onChange(of: isCaptured) { _, captured in
            if captured { security.lock(); location.stop() }
        }
    }

    private func prepare() async {
        guard security.isUnlocked else { return }
        do {
            if store == nil {
                let files = try SecureFiles()
                store = LocalStore(files: files)
                maps = MapRepository(files: files)
            }
            try store?.load()
            try await maps?.load()
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
