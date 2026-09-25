import SwiftUI

enum MapStyle: String, CaseIterable {
    case vector = "Vector"
    case photo = "Photo"
    case terrain = "3D"
}
enum DrawTool: String, CaseIterable {
    case point = "Point"
    case line = "Line"
    case area = "Area"
    var kind: AnnotationKind {
        switch self {
        case .point: .point
        case .line: .line
        case .area: .area
        }
    }
    var symbol: String {
        switch self {
        case .point: "mappin"
        case .line: "point.topleft.down.to.point.bottomright.curvepath"
        case .area: "pentagon"
        }
    }
}

struct MapScreen: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(AppNavigation.self) private var navigation
    let store: LocalStore
    let maps: MapRepository
    let location: LocationService
    @State private var style = MapStyle.vector
    @State private var viewport = MapViewport()
    @State private var activeLayer = TacticalLayer.blue
    @State private var visibleLayers = Set(TacticalLayer.allCases)
    @State private var tool: DrawTool?
    @State private var draft: [Coordinate] = []
    @State private var editing: MapAnnotation?
    @State private var pendingSelection: MapAnnotation?
    @AppStorage("showRegionBorders") private var showRegionBorders = true
    @State private var showLayers = false
    @State private var showCredits = false
    @State private var error: String?
    @State private var size = CGSize(width: 390, height: 620)
    @State private var fitted = false
    @State private var waitingForGPS = false

    private var visibleAnnotations: [MapAnnotation] { store.annotations.filter { visibleLayers.contains($0.layer) } }
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        ZStack {
            if navigation.section == .map {
                mapSurface.ignoresSafeArea()
                VStack(spacing: 8) {
                    HStack(alignment: .top) {
                        AppMenu()
                        Spacer(minLength: 8)
                        coordinateBar.frame(height: 46)
                        Spacer(minLength: 8)
                        if isLandscape {
                            HStack(spacing: 6) { mapButtons }
                        } else {
                            VStack(spacing: 6) { mapButtons }
                        }
                    }
                    Spacer(minLength: 4)
                    if style != .terrain {
                        HStack {
                            Spacer()
                            Button("© OpenStreetMap") { showCredits = true }
                                .font(.system(size: 10)).foregroundStyle(Theme.muted)
                                .padding(6).background(Theme.panel.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                                .accessibilityLabel("Map credits")
                        }
                    }
                    if navigation.selectingPosition { positionBar } else if tool != nil { drawingBar } else { layerBar }
                }
                .padding(.horizontal, isLandscape ? 8 : 12)
                .padding(.top, isLandscape ? 8 : 12)
                .padding(.bottom, 2)
            }
        }
        .background(Theme.background)
        .onGeometryChange(for: CGSize.self) {
            $0.size
        } action: { newSize in
            size = newSize
            if !fitted, newSize.height > 0 {
                if let focus = maps.regionFocus {
                    viewport.center = focus.worldPoint
                    viewport.zoom = 13
                } else {
                    viewport.fit(.sweden, size: newSize)
                }
                fitted = true
            }
        }
        .onChange(of: navigation.selectingPosition) { _, selecting in
            if selecting {
                style = .vector
                tool = nil
                draft = []
            }
        }
        .onChange(of: maps.regionFocus) { _, coordinate in
            if let coordinate {
                viewport.center = coordinate.worldPoint
                viewport.zoom = 12
                style = .vector
            }
        }
        .onChange(of: location.fix) { _, _ in
            if waitingForGPS, let position = location.currentPosition {
                viewport.center = position.coordinate.worldPoint
                viewport.zoom = 15
                waitingForGPS = false
            }
        }
        .sheet(
            isPresented: $showLayers,
            onDismiss: {
                if let pendingSelection {
                    editing = pendingSelection
                    self.pendingSelection = nil
                }
            }
        ) {
            LayerSheet(store: store, visible: $visibleLayers, showRegionBorders: $showRegionBorders) { annotation in
                pendingSelection = annotation
                showLayers = false
                if let c = annotation.coordinates.first {
                    viewport.center = c.worldPoint
                    viewport.zoom = 15
                    style = .vector
                }
            }
        }
        .sheet(isPresented: $showCredits) {
            NavigationStack {
                MapCredits(maps: maps)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showCredits = false } } }
            }
        }
        .sheet(item: $editing) { AnnotationEditor(annotation: $0, store: store) }
        .alert("Map", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var mapSurface: some View {
        ZStack {
            if let package = maps.package {
                if style == .terrain {
                    TerrainView(
                        package: package, photo: maps.photo, annotations: visibleAnnotations,
                        coverage: showRegionBorders ? maps.loadedRegions : []
                    ).id(maps.revision)
                } else {
                    TimelineView(.periodic(from: .now, by: 5)) { _ in
                        OfflineVectorMap(
                            maps: maps, photoMode: style == .photo, showRegionBorders: showRegionBorders,
                            viewport: $viewport,
                            annotations: store.annotations, visibleLayers: visibleLayers, draft: draft,
                            activeLayer: activeLayer,
                            location: location.currentPosition, callsign: store.callsign, onTap: mapTapped
                        )
                        .id("\(maps.revision)-\(style.rawValue)")
                    }
                }
            } else {
                ProgressView()
            }
            // The crosshair shares the full map bounds so it matches the camera center.
            if style != .terrain {
                Image(systemName: "plus").font(.system(size: 22, weight: .light))
                    .foregroundStyle(.white.opacity(0.8)).shadow(color: .black, radius: 2)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
    }

    @ViewBuilder private var mapButtons: some View {
        Menu {
            ForEach(MapStyle.allCases, id: \.self) { option in
                Button(option.rawValue, systemImage: style == option ? "checkmark" : "map") {
                    style = option
                    tool = nil
                    draft = []
                    navigation.selectingPosition = false
                }
            }
            Button("Show Sweden", systemImage: "arrow.up.left.and.arrow.down.right") {
                viewport.fit(.sweden, size: size)
                style = .vector
            }
        } label: {
            Text(style.rawValue).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white).frame(width: 46, height: 46)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
        }.accessibilityLabel("Map mode").accessibilityValue(style.rawValue)
        PanelButton(symbol: "square.3.layers.3d", label: "Layers") { showLayers = true }
        if style != .terrain {
            Menu {
                Text(positionStatus)
                if let position = location.currentPosition {
                    Button("Center on my position", systemImage: "location.fill") {
                        viewport.center = position.coordinate.worldPoint
                        viewport.zoom = 15
                    }
                }
                Button("Set my position on map", systemImage: "mappin.and.ellipse") {
                    navigation.selectingPosition = true
                    tool = nil
                    draft = []
                }
                Button(location.isEnabled ? "Turn GPS off" : "Enable GPS", systemImage: "location") {
                    if location.isEnabled {
                        location.stop()
                        waitingForGPS = false
                    } else {
                        location.enable()
                        waitingForGPS = true
                    }
                }
                if store.ownPosition != nil {
                    Button("Clear manual position", role: .destructive) {
                        do {
                            try store.setOwnPosition(nil)
                            location.manualPosition = nil
                        } catch { self.error = error.localizedDescription }
                    }
                }
            } label: {
                Image(systemName: location.isEnabled ? "location.fill" : "location")
                    .font(.system(size: 19)).foregroundStyle(location.isEnabled ? Theme.accent : .white)
                    .frame(width: 46, height: 46).background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
            }.accessibilityLabel("My position")
            PanelButton(symbol: "plus", label: "Zoom in") {
                viewport.zoom += 1
                viewport.clamp()
            }
            PanelButton(symbol: "minus", label: "Zoom out") {
                viewport.zoom -= 1
                viewport.clamp()
            }
        }
    }

    private var layerBar: some View {
        HStack(spacing: 6) {
            ForEach(TacticalLayer.allCases) { layer in
                Button {
                    activeLayer = layer
                    visibleLayers.insert(layer)
                } label: {
                    Text(layer.rawValue).font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(layer.color).frame(maxWidth: isLandscape ? 80 : .infinity).frame(height: 44)
                        .background {
                            RoundedRectangle(cornerRadius: 12).fill(Theme.panel)
                                .overlay {
                                    if activeLayer == layer {
                                        RoundedRectangle(cornerRadius: 12).fill(layer.color.opacity(0.20))
                                    }
                                }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12).strokeBorder(
                                activeLayer == layer ? layer.color : Theme.line,
                                lineWidth: activeLayer == layer ? 1.5 : 1)
                        }
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                }.accessibilityLabel("\(layer.rawValue), \(layer.title)").accessibilityAddTraits(
                    activeLayer == layer ? [.isSelected] : [])
            }
            if isLandscape { Spacer(minLength: 4) }
            if style != .terrain {
                Menu {
                    ForEach(DrawTool.allCases, id: \.self) { option in
                        Button(option.rawValue, systemImage: option.symbol) {
                            tool = option
                            draft = []
                            visibleLayers.insert(activeLayer)
                        }
                    }
                } label: {
                    Label("Annotate", systemImage: "pencil.tip").fixedSize(horizontal: true, vertical: false)
                        .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 12).frame(height: 44)
                        .foregroundStyle(Theme.background).background(
                            Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                }.accessibilityIdentifier("annotate")
            }
        }
    }

    private var positionBar: some View {
        HStack(spacing: 12) {
            Button("Cancel") { navigation.selectingPosition = false }
            Spacer(minLength: 0)
            Button("Set position here", systemImage: "mappin.and.ellipse") {
                setPosition(Coordinate(worldPoint: viewport.center))
            }
            .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("set-own-position")
        }.padding(10).background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private var drawingBar: some View {
        VStack(spacing: 6) {
            HStack {
                Label(tool?.rawValue ?? "", systemImage: tool?.symbol ?? "pencil").foregroundStyle(activeLayer.color)
                Spacer()
                Button("Cancel") {
                    tool = nil
                    draft = []
                }
            }
            HStack {
                Button("Use map center") { mapTapped(Coordinate(worldPoint: viewport.center)) }.frame(minHeight: 44)
                Spacer(minLength: 4)
                if tool != .point {
                    Button {
                        if !draft.isEmpty { draft.removeLast() }
                    } label: {
                        Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44)
                    }
                    .disabled(draft.isEmpty).accessibilityLabel("Undo vertex")
                    Button("Save \(draft.count)") { finishDrawing() }.buttonStyle(PrimaryButtonStyle())
                        .disabled(draft.count < (tool == .area ? 3 : 2))
                }
            }
        }.font(.subheadline).padding(12).background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private var coordinateBar: some View {
        Text(Coordinate(worldPoint: viewport.center).formatted)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Theme.panel, in: Capsule())
            .fixedSize()
            .accessibilityIdentifier("map-mgrs")
            .accessibilityLabel("MGRS map center")
            .accessibilityValue(Coordinate(worldPoint: viewport.center).formatted)
    }
    private var positionStatus: String {
        if location.isEnabled { return location.currentPosition == nil ? "GPS: no fix" : location.message }
        return location.manualPosition == nil ? "GPS off" : "Manual position"
    }
    private func setPosition(_ coordinate: Coordinate) {
        let position = PositionSnapshot(coordinate: coordinate, source: .manual, timestamp: Date())
        do {
            try store.setOwnPosition(position)
            location.stop()
            location.manualPosition = position
            navigation.selectingPosition = false
        } catch { self.error = error.localizedDescription }
    }
    private func mapTapped(_ coordinate: Coordinate) {
        if navigation.selectingPosition {
            viewport.center = coordinate.worldPoint
            return
        }
        guard let tool else {
            let nearest = visibleAnnotations.filter { $0.kind == .point }.min {
                distance($0.coordinates[0], coordinate) < distance($1.coordinates[0], coordinate)
            }
            if let nearest, distance(nearest.coordinates[0], coordinate) < 24 { editing = nearest }
            return
        }
        guard MapBounds.sweden.contains(coordinate) else {
            error = "Place annotations within Sweden map coverage."
            return
        }
        guard draft.count < 10_000 else {
            error = "This drawing has reached its vertex limit."
            return
        }
        if tool == .point {
            editing = MapAnnotation(layer: activeLayer, kind: .point, title: "", coordinates: [coordinate])
            self.tool = nil
        } else {
            draft.append(coordinate)
        }
    }
    private func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        hypot(a.worldPoint.x - b.worldPoint.x, a.worldPoint.y - b.worldPoint.y) * viewport.scale
    }
    private func finishDrawing() {
        guard let tool else { return }
        guard Set(draft).count >= (tool == .area ? 3 : 2) else {
            error = "Add distinct locations before saving."
            return
        }
        editing = MapAnnotation(layer: activeLayer, kind: tool.kind, title: "", coordinates: draft)
        self.tool = nil
        draft = []
    }
}
