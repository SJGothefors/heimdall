@preconcurrency import MapLibre

/// Saved objects, the active drawing and own position change independently.
/// Camera movement must not serialize or resubmit any of them.
@MainActor final class MapOverlayRenderer {
    enum Source: String, CaseIterable { case objects, draft, position }
    struct Update {
        let source: Source
        let shape: MLNShapeCollectionFeature
    }
    private struct Drawing: Equatable {
        let coordinates: [Coordinate]
        let layer: TacticalLayer
    }
    private struct Marker: Equatable {
        let coordinate: Coordinate
        let title: String
    }
    private var annotations: [MapAnnotation]?
    private var drawing: Drawing?
    private var marker: Marker?
    private var hasPosition = false

    func invalidate() {
        annotations = nil
        drawing = nil
        hasPosition = false
    }

    func updates(
        annotations: [MapAnnotation], draft: [Coordinate], layer: TacticalLayer,
        position: PositionSnapshot?, callsign: String
    ) -> [Update] {
        var result: [Update] = []
        if self.annotations != annotations {
            let shapes = annotations.compactMap {
                Self.feature($0.coordinates, kind: $0.kind, layer: $0.layer.rawValue, title: $0.title)
            }
            result.append(Update(source: .objects, shape: MLNShapeCollectionFeature(shapes: shapes)))
            self.annotations = annotations
        }
        let drawing = Drawing(coordinates: draft, layer: layer)
        if self.drawing != drawing {
            var shapes: [MLNShape & MLNFeature] = []
            if draft.count >= 2, let line = Self.feature(draft, kind: .line, layer: layer.rawValue, title: "") {
                shapes.append(line)
            }
            shapes.append(
                contentsOf: draft.compactMap {
                    Self.feature([$0], kind: .point, layer: layer.rawValue, title: "")
                })
            result.append(Update(source: .draft, shape: MLNShapeCollectionFeature(shapes: shapes)))
            self.drawing = drawing
        }
        let marker = position.map {
            Marker(coordinate: $0.coordinate, title: callsign.isEmpty ? $0.source.rawValue.uppercased() : callsign)
        }
        if !hasPosition || self.marker != marker {
            let shapes =
                marker.flatMap {
                    Self.feature([$0.coordinate], kind: .point, layer: "OWN", title: $0.title)
                }.map { [$0] } ?? []
            result.append(Update(source: .position, shape: MLNShapeCollectionFeature(shapes: shapes)))
            self.marker = marker
            hasPosition = true
        }
        return result
    }

    private static func feature(
        _ coordinates: [Coordinate], kind: AnnotationKind, layer: String, title: String
    ) -> (MLNShape & MLNFeature)? {
        guard let first = coordinates.first else { return nil }
        let feature: MLNShape & MLNFeature
        switch kind {
        case .point:
            let point = MLNPointFeature()
            point.coordinate = CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)
            feature = point
        case .line:
            guard coordinates.count >= 2 else { return nil }
            let points = coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            feature = MLNPolylineFeature(coordinates: points, count: UInt(points.count))
        case .area:
            guard coordinates.count >= 3 else { return nil }
            let points = (coordinates + [first]).map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            feature = MLNPolygonFeature(coordinates: points, count: UInt(points.count))
        }
        feature.attributes = ["layer": layer, "name": title]
        return feature
    }
}
