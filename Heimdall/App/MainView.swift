import Observation
import SwiftUI

enum AppSection: String, CaseIterable {
    case map = "Map"
    case reports = "7S reports"
    case media = "Media"
    case device = "Device"
    var symbol: String {
        switch self {
        case .map: "map"
        case .reports: "text.document"
        case .media: "camera"
        case .device: "shield.lefthalf.filled"
        }
    }
}

@MainActor @Observable final class AppNavigation {
    var section = AppSection.map
    var selectingPosition = false
}

struct AppMenu: View {
    @Environment(AppNavigation.self) private var navigation
    var body: some View {
        Menu {
            ForEach(AppSection.allCases, id: \.self) { section in
                Button(section.rawValue, systemImage: section.symbol) { navigation.section = section }
            }
        } label: {
            Image(systemName: "line.3.horizontal").font(.system(size: 19, weight: .medium))
                .foregroundStyle(.white).frame(width: 46, height: 46)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
        }.accessibilityLabel("Navigation menu").accessibilityIdentifier("navigation-menu")
    }
}

struct MainView: View {
    let store: LocalStore
    let maps: MapRepository
    let location: LocationService
    let security: DeviceSecurity
    @State private var navigation = AppNavigation()

    var body: some View {
        ZStack {
            // Keep the map's camera and unfinished drawing when changing sections.
            MapScreen(store: store, maps: maps, location: location)
            switch navigation.section {
            case .map: EmptyView()
            case .reports: ReportsScreen(store: store, location: location)
            case .media: MediaScreen(store: store)
            case .device: SettingsScreen(store: store, maps: maps, location: location, security: security)
            }
        }.environment(navigation)
    }
}
