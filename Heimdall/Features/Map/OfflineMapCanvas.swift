import SwiftUI

struct OfflineMapCanvas: View {
    let package: MapPackage
    let photo: UIImage?
    let photoMode: Bool
    @Binding var viewport: MapViewport
    let annotations: [MapAnnotation]
    let draft: [Coordinate]
    let activeLayer: TacticalLayer
    let drawing: Bool
    let location: Coordinate?
    let onTap: (Coordinate) -> Void
    @State private var panOrigin: CGPoint?
    @State private var zoomOrigin: Double?

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.052, green: 0.090, blue: 0.103)))
                if photoMode, let photo {
                    let nw = viewport.screenPoint(Coordinate(latitude: package.bounds.north, longitude: package.bounds.west), size: size)
                    let se = viewport.screenPoint(Coordinate(latitude: package.bounds.south, longitude: package.bounds.east), size: size)
                    context.draw(Image(uiImage: photo), in: CGRect(x: nw.x, y: nw.y, width: se.x-nw.x, height: se.y-nw.y))
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.22)))
                } else {
                    drawFeatures(context: &context, size: size)
                }
                drawGrid(context: &context, size: size)
                drawPlaces(context: &context, size: size)
                for annotation in annotations { draw(annotation, context: &context, size: size) }
                if !draft.isEmpty {
                    draw(MapAnnotation(layer: activeLayer, kind: .line, title: "", coordinates: draft), context: &context, size: size)
                    for coordinate in draft {
                        let p = viewport.screenPoint(coordinate, size: size)
                        context.fill(Path(ellipseIn: CGRect(x: p.x-4, y: p.y-4, width: 8, height: 8)), with: .color(activeLayer.color))
                    }
                }
                if let location {
                    let p = viewport.screenPoint(location, size: size)
                    context.fill(Path(ellipseIn: CGRect(x: p.x-13, y: p.y-13, width: 26, height: 26)), with: .color(.white.opacity(0.12)))
                    context.fill(Path(ellipseIn: CGRect(x: p.x-5, y: p.y-5, width: 10, height: 10)), with: .color(.white))
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if panOrigin == nil { panOrigin = viewport.center }
                    guard let origin = panOrigin else { return }
                    viewport.center = CGPoint(x: origin.x - value.translation.width / viewport.scale,
                                              y: origin.y - value.translation.height / viewport.scale)
                    viewport.clamp()
                }.onEnded { _ in panOrigin = nil })
            .simultaneousGesture(MagnifyGesture().onChanged { value in
                if zoomOrigin == nil { zoomOrigin = viewport.zoom }
                viewport.zoom = (zoomOrigin ?? viewport.zoom) + log2(value.magnification)
                viewport.clamp()
            }.onEnded { _ in zoomOrigin = nil })
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                onTap(viewport.coordinate(at: value.location, size: geometry.size))
            })
            .accessibilityLabel("Offline Sweden map")
            .accessibilityHint(drawing ? "Tap to add points. Use the center-point button with VoiceOver." : "Pinch to zoom and drag to pan. Map objects are also available in Layers.")
        }
    }

    private func path(_ coordinates: [Coordinate], size: CGSize, close: Bool) -> Path {
        Path { path in
            for (index, coordinate) in coordinates.enumerated() {
                let point = viewport.screenPoint(coordinate, size: size)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            if close { path.closeSubpath() }
        }
    }

    private func drawFeatures(context: inout GraphicsContext, size: CGSize) {
        for feature in package.features {
            var combined = Path()
            for ring in feature.paths { combined.addPath(path(ring, size: size, close: feature.kind == .land || feature.kind == .water)) }
            guard combined.boundingRect.intersects(CGRect(origin: .zero, size: size)) else { continue }
            switch feature.kind {
            case .land:
                context.fill(combined, with: .color(Color(red: 0.115, green: 0.16, blue: 0.155)), style: FillStyle(eoFill: true))
                context.stroke(combined, with: .color(Color(red: 0.28, green: 0.36, blue: 0.32)), lineWidth: 0.8)
            case .water:
                context.fill(combined, with: .color(Color(red: 0.052, green: 0.090, blue: 0.103)), style: FillStyle(eoFill: true))
            case .river:
                if viewport.zoom > 5 { context.stroke(combined, with: .color(Color(red: 0.17, green: 0.28, blue: 0.31)), lineWidth: 0.8) }
            case .road:
                context.stroke(combined, with: .color(Color(red: 0.52, green: 0.51, blue: 0.37).opacity(viewport.zoom > 6 ? 0.7 : 0.3)), lineWidth: viewport.zoom > 7 ? 1.5 : 0.7)
            }
        }
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        let step = viewport.zoom > 9 ? 0.1 : (viewport.zoom > 6 ? 0.5 : 2.0)
        let upper = viewport.coordinate(at: .zero, size: size)
        let lower = viewport.coordinate(at: CGPoint(x: size.width, y: size.height), size: size)
        var grid = Path()
        for lon in stride(from: floor(upper.longitude / step) * step, through: lower.longitude, by: step) {
            let x = viewport.screenPoint(Coordinate(latitude: 60, longitude: lon), size: size).x
            grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
        }
        for lat in stride(from: floor(lower.latitude / step) * step, through: upper.latitude, by: step) {
            let y = viewport.screenPoint(Coordinate(latitude: lat, longitude: 15), size: size).y
            grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(grid, with: .color(.white.opacity(0.055)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 5]))
    }

    private func drawPlaces(context: inout GraphicsContext, size: CGSize) {
        var occupied: [CGRect] = []
        for place in package.places.sorted(by: { $0.population > $1.population }) {
            if viewport.zoom < 6 && place.population < 70_000 { continue }
            let p = viewport.screenPoint(place.coordinate, size: size)
            let rect = CGRect(x: p.x-3, y: p.y-5, width: Double(place.name.count)*7+15, height: 23)
            guard rect.intersects(CGRect(origin: .zero, size: size)), !occupied.contains(where: { $0.intersects(rect) }) else { continue }
            occupied.append(rect.insetBy(dx: -8, dy: -8))
            context.fill(Path(ellipseIn: CGRect(x: p.x-2, y: p.y-2, width: 4, height: 4)), with: .color(.white.opacity(0.65)))
            context.draw(Text(place.name).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7)),
                         at: CGPoint(x: p.x+7, y: p.y), anchor: .leading)
        }
    }

    private func draw(_ annotation: MapAnnotation, context: inout GraphicsContext, size: CGSize) {
        guard let first = annotation.coordinates.first else { return }
        let color = annotation.layer.color
        let p = viewport.screenPoint(first, size: size)
        if annotation.kind == .point {
            let symbol = Image(systemName: annotation.layer == .blue ? "rectangle.fill" : (annotation.layer == .red ? "diamond.fill" : "mappin.circle.fill"))
            context.draw(Text(symbol).font(.system(size: 20)).foregroundStyle(color), at: p)
        } else {
            let outline = path(annotation.coordinates, size: size, close: annotation.kind == .area)
            if annotation.kind == .area { context.fill(outline, with: .color(color.opacity(0.12))) }
            context.stroke(outline, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        if !annotation.title.isEmpty {
            context.draw(Text(annotation.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(color),
                         at: CGPoint(x: p.x+14, y: p.y-13), anchor: .leading)
        }
    }
}
