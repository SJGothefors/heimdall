import SwiftUI

enum MapStyle: String, CaseIterable { case vector = "Vector", photo = "Photo", terrain = "3D" }
enum DrawTool: String, CaseIterable {
    case point = "Point", line = "Line", area = "Area"
    var kind: AnnotationKind { switch self { case .point: .point; case .line: .line; case .area: .area } }
    var symbol: String { switch self { case .point: "mappin"; case .line: "point.topleft.down.to.point.bottomright.curvepath"; case .area: "pentagon" } }
}

struct MapScreen: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
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
    @State private var showLayers = false
    @State private var error: String?
    @State private var size = CGSize(width: 390, height: 620)
    @State private var fitted = false

    private var visibleAnnotations: [MapAnnotation] { store.annotations.filter { visibleLayers.contains($0.layer) } }
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        VStack(spacing: 0) {
            if !isLandscape { header }
            ZStack {
                if let package = maps.package {
                    if style == .terrain {
                        TerrainView(package: package, photo: maps.photo, annotations: visibleAnnotations)
                            .id(maps.revision)
                            .overlay(alignment: .bottom) {
                                Text("Drag to orbit · pinch to zoom · relief ×12")
                                    .font(.caption2).padding(10).background(Theme.panel, in: Capsule()).padding(.bottom, isLandscape ? 64 : 92)
                            }
                    } else {
                        TimelineView(.periodic(from: .now, by: 10)) { _ in
                            OfflineMapCanvas(package: package, photo: maps.photo, photoMode: style == .photo,
                                viewport: $viewport, annotations: visibleAnnotations, draft: draft,
                                activeLayer: activeLayer, drawing: tool != nil, location: location.freshCoordinate, onTap: mapTapped)
                        }
                    }
                } else { ProgressView("Loading local map…") }
                if isLandscape { landscapeControls } else { mapControls }
                if style != .terrain {
                    Image(systemName: "plus").font(.system(size: 22, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.6)).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .clipped()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { newSize in
                size = newSize
                if !fitted, newSize.height > 0 { viewport.fit(maps.package?.bounds ?? .sweden, size: newSize); fitted = true }
            }
            .onChange(of: maps.revision) { _, _ in viewport.fit(maps.package?.bounds ?? .sweden, size: size) }
            footer
        }
        .sheet(isPresented: $showLayers, onDismiss: {
            if let pendingSelection { editing = pendingSelection; self.pendingSelection = nil }
        }) {
            LayerSheet(store: store, visible: $visibleLayers, active: $activeLayer) { annotation in
                pendingSelection = annotation
                showLayers = false
                if let c = annotation.coordinates.first { viewport.center = c.worldPoint; viewport.zoom = 10; style = .vector }
            }
        }
        .sheet(item: $editing) { annotation in
            AnnotationEditor(annotation: annotation, store: store)
        }
        .alert("Map", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: "LOCAL SITUATIONAL AWARENESS")
                Text("Field map").font(.system(size: 29, weight: .semibold, design: .rounded))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Label("OFFLINE", systemImage: "circle.fill").font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                Text("SWEDEN").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(Theme.muted)
            }
        }.padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 18).background(Theme.background)
    }

    private var landscapeControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                stylePicker
                Spacer(minLength: 4)
                mapBadge
                PanelButton(symbol: "square.3.layers.3d", label: "Layers") { showLayers = true }
            }
            if style != .terrain {
                HStack {
                    Spacer()
                    HStack(spacing: 6) { navigationButtons }
                }
            }
            Spacer(minLength: 4)
            if let tool {
                HStack(spacing: 16) {
                    Label("\(tool.rawValue) · \(activeLayer.rawValue)", systemImage: tool.symbol)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(activeLayer.color)
                    Text(tool == .point ? "Tap to place" : "Tap to add vertices")
                        .font(.caption).foregroundStyle(Theme.muted)
                    Spacer(minLength: 0)
                    Button("Use map center") { mapTapped(Coordinate(worldPoint: viewport.center)) }.font(.caption)
                    if tool != .point {
                        Button { if !draft.isEmpty { draft.removeLast() } } label: { Image(systemName: "arrow.uturn.backward") }
                            .disabled(draft.isEmpty).frame(minWidth: 44, minHeight: 44).accessibilityLabel("Undo vertex")
                        Button("Save \(draft.count)") { finishDrawing() }.buttonStyle(.borderedProminent)
                            .disabled(draft.count < (tool == .area ? 3 : 2))
                    }
                    Button("Cancel") { self.tool = nil; draft = [] }.font(.caption).frame(minHeight: 44)
                }.padding(.horizontal, 14).padding(.vertical, 4).background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
            } else {
                HStack(spacing: 16) {
                    layerSwitcher.frame(maxWidth: 340)
                    Spacer(minLength: 0)
                    if style != .terrain {
                        Text(scaleLabel).font(.system(size: 10, design: .monospaced))
                            .padding(10).background(Theme.background.opacity(0.85), in: Capsule())
                        annotateMenu
                    }
                }
            }
        }.padding(12)
    }

    private var stylePicker: some View {
        HStack(spacing: 2) {
            ForEach(MapStyle.allCases, id: \.self) { option in
                Button { style = option; tool = nil; draft = [] } label: {
                    Text(option.rawValue).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 17).frame(height: 36)
                        .foregroundStyle(style == option ? Theme.background : Theme.muted)
                        .background(style == option ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 10))
                }.accessibilityAddTraits(style == option ? [.isSelected] : [])
            }
        }.padding(4).background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private var mapBadge: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(maps.package?.name ?? "Sweden").font(.system(size: 11, weight: .semibold))
            Text(maps.isImported ? (maps.package?.detail ?? "") : "OVERVIEW · LOW DETAIL")
                .font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(0.8).foregroundStyle(Theme.muted)
                .lineLimit(isLandscape ? 1 : 3)
            if let package = maps.package, !package.bounds.contains(Coordinate(worldPoint: viewport.center)), style != .terrain {
                Text("Outside active map coverage").font(.caption2).foregroundStyle(.orange)
            }
        }.padding(10).background(Theme.background.opacity(0.88), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var navigationButtons: some View {
        PanelButton(symbol: "location", label: "Locate me", active: location.isEnabled) {
            if let coordinate = location.freshCoordinate {
                if MapBounds.sweden.contains(coordinate) { viewport.center = coordinate.worldPoint; viewport.zoom = 11 }
                else { error = "Your position is outside the Sweden map coverage." }
            } else { location.enable() }
        }
        PanelButton(symbol: "plus", label: "Zoom in") { viewport.zoom += 1; viewport.clamp() }
        PanelButton(symbol: "minus", label: "Zoom out") { viewport.zoom -= 1; viewport.clamp() }
        PanelButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Show Sweden") { viewport.fit(maps.package?.bounds ?? .sweden, size: size) }
    }

    private var layerSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(TacticalLayer.allCases) { layer in
                Button {
                    activeLayer = layer
                    visibleLayers.insert(layer)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: layer.symbol).font(.system(size: 11, weight: .bold))
                        Text(layer.rawValue).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(0.6)
                        Spacer(minLength: 0)
                        Text("\(store.annotations.filter { $0.layer == layer }.count)").font(.system(size: 10, design: .monospaced))
                    }.foregroundStyle(layer.color).padding(.horizontal, 12).frame(height: 44)
                        .background(activeLayer == layer ? layer.color.opacity(0.13) : Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(activeLayer == layer ? layer.color.opacity(0.5) : Theme.line))
                }.accessibilityLabel("\(layer.rawValue), \(layer.title)").accessibilityAddTraits(activeLayer == layer ? [.isSelected] : [])
            }
        }
    }

    private var annotateMenu: some View {
        Menu {
            ForEach(DrawTool.allCases, id: \.self) { option in
                Button(option.rawValue, systemImage: option.symbol) { tool = option; draft = []; visibleLayers.insert(activeLayer) }
            }
        } label: {
            Label("Annotate", systemImage: "pencil.tip.crop.circle.badge.plus")
                .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 17).frame(height: 46)
                .foregroundStyle(Theme.background).background(Theme.accent, in: Capsule())
        }.accessibilityIdentifier("annotate")
    }

    private var mapControls: some View {
        VStack(spacing: 12) {
            HStack {
                stylePicker
                Spacer(minLength: 6)
                PanelButton(symbol: "square.3.layers.3d", label: "Layers") { showLayers = true }
            }
            HStack(alignment: .top) {
                mapBadge
                Spacer()
                if style != .terrain {
                    VStack(spacing: 8) { navigationButtons }
                }
            }
            Spacer()
            if let tool {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: tool.symbol).foregroundStyle(activeLayer.color)
                        Text("\(tool.rawValue) · \(activeLayer.rawValue)").font(.subheadline.weight(.semibold))
                        Spacer()
                        Button("Cancel") { self.tool = nil; draft = [] }.font(.caption)
                    }
                    Text(tool == .point ? "Tap the map to place a point." : "Tap to add vertices. Pan or zoom between points.")
                        .font(.caption).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Button("Use map center") { mapTapped(Coordinate(worldPoint: viewport.center)) }.font(.caption)
                        Spacer()
                        if tool != .point {
                            Button { if !draft.isEmpty { draft.removeLast() } } label: { Image(systemName: "arrow.uturn.backward") }
                                .disabled(draft.isEmpty).accessibilityLabel("Undo vertex")
                            Button("Save \(draft.count)") { finishDrawing() }
                                .buttonStyle(.borderedProminent).disabled(draft.count < (tool == .area ? 3 : 2))
                        }
                    }
                }.padding(16).background(Theme.panel, in: RoundedRectangle(cornerRadius: 18))
            } else {
                HStack(alignment: .bottom) {
                    if style != .terrain {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 4) { Rectangle().frame(width: 1, height: 6); Rectangle().frame(width: 56, height: 1); Rectangle().frame(width: 1, height: 6) }
                            Text(scaleLabel).font(.system(size: 9, design: .monospaced))
                        }.foregroundStyle(.white.opacity(0.6)).padding(10).background(Theme.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                    }
                    Spacer()
                    if style != .terrain {
                        annotateMenu
                    }
                }
            }
            if tool == nil {
                layerSwitcher
            }
        }.padding(16)
    }

    private var scaleLabel: String {
        let meters = viewport.metersPerPoint * 56
        return meters >= 1_000 ? String(format: "%.1f km", meters / 1_000) : "\(Int(meters)) m"
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(Coordinate(worldPoint: viewport.center).formatted).font(.system(size: 10, weight: .medium, design: .monospaced))
                Text("WGS 84 · MAP CENTER").font(.system(size: 8, design: .monospaced)).tracking(1).foregroundStyle(Theme.muted)
            }
            Spacer()
            TimelineView(.periodic(from: .now, by: 10)) { _ in
                Text(location.isEnabled && location.freshCoordinate == nil ? "No fresh GPS fix" : location.message)
                    .font(.system(size: 9)).foregroundStyle(Theme.muted).multilineTextAlignment(.trailing)
            }
        }.padding(.horizontal, 20).padding(.vertical, isLandscape ? 6 : 13).background(Theme.background)
    }

    private func mapTapped(_ coordinate: Coordinate) {
        guard let tool else {
            let nearest = visibleAnnotations.filter { $0.kind == .point }.min {
                distance($0.coordinates[0], coordinate) < distance($1.coordinates[0], coordinate)
            }
            if let nearest, distance(nearest.coordinates[0], coordinate) < 24 { editing = nearest }
            return
        }
        guard MapBounds.sweden.contains(coordinate) else { error = "Place annotations within Sweden map coverage."; return }
        guard draft.count < 10_000 else { error = "This drawing has reached its vertex limit."; return }
        if tool == .point {
            editing = MapAnnotation(layer: activeLayer, kind: .point, title: "", coordinates: [coordinate])
            self.tool = nil
        } else { draft.append(coordinate) }
    }

    private func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        hypot(a.worldPoint.x-b.worldPoint.x, a.worldPoint.y-b.worldPoint.y) * viewport.scale
    }

    private func finishDrawing() {
        guard let tool else { return }
        guard Set(draft).count >= (tool == .area ? 3 : 2) else {
            error = "Add \(tool == .area ? 3 : 2) different locations before saving."
            return
        }
        editing = MapAnnotation(layer: activeLayer, kind: tool.kind, title: "", coordinates: draft)
        self.tool = nil; draft = []
    }
}
