import SwiftUI

struct MainView: View {
    let store: LocalStore
    let maps: MapRepository
    let location: LocationService
    let security: DeviceSecurity
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            Tab("Map", systemImage: "map", value: 0) {
                MapScreen(store: store, maps: maps, location: location)
            }
            Tab("7S reports", systemImage: "text.document", value: 1) {
                ReportsScreen(store: store)
            }
            Tab("Media", systemImage: "camera", value: 2) {
                MediaScreen(store: store)
            }
            Tab("Device", systemImage: "shield.lefthalf.filled", value: 3) {
                SettingsScreen(store: store, maps: maps, location: location, security: security)
            }
        }.toolbarBackground(Theme.background, for: .tabBar).toolbarBackground(.visible, for: .tabBar)
    }
}
