@preconcurrency import MapLibre
import SwiftUI

/// MapLibre reads only bundled/local sources. Fail closed if a renderer ever
/// attempts an HTTP request (including a missing glyph or style fallback).
final class OfflineMapProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        ["http", "https"].contains(request.url?.scheme ?? "")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}

struct OfflineVectorMap: UIViewRepresentable {
    let maps: MapRepository
    let photoMode: Bool
    let showRegionBorders: Bool
    @Binding var viewport: MapViewport
    let annotations: [MapAnnotation]
    let draft: [Coordinate]
    let activeLayer: TacticalLayer
    let location: PositionSnapshot?
    let callsign: String
    let onTap: (Coordinate) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MLNMapView {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineMapProtocol.self]
        configuration.urlCache = nil
        MLNNetworkConfiguration.sharedManager.sessionConfiguration = configuration
        let map = MLNMapView(frame: .zero, styleJSON: OfflineMapStyle.json(maps: maps, photo: photoMode))
        context.coordinator.settingCamera = true
        map.delegate = context.coordinator
        map.automaticallyAdjustsContentInset = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.minimumZoomLevel = 1
        map.maximumZoomLevel = 19
        map.compassView.isHidden = true
        map.logoView.isHidden = true
        // The SwiftUI overlay provides local map credits without opening a web view.
        map.attributionButton.isHidden = true
        map.showsUserLocation = false
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        map.addGestureRecognizer(tap)
        for recognizer in map.gestureRecognizers ?? [] {
            if let other = recognizer as? UITapGestureRecognizer, other !== tap, other.numberOfTapsRequired > 1 {
                tap.require(toFail: other)
            }
        }
        map.setCenter(Coordinate(worldPoint: viewport.center).clLocation, zoomLevel: viewport.zoom, animated: false)
        context.coordinator.settingCamera = false
        map.accessibilityLabel = "Offline Sweden map"
        return map
    }
    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.parent = self
        let center = Coordinate(worldPoint: viewport.center)
        if abs(map.zoomLevel - viewport.zoom) > 0.001 || abs(map.centerCoordinate.latitude - center.latitude) > 0.000001
            || abs(map.centerCoordinate.longitude - center.longitude) > 0.000001
        {
            context.coordinator.settingCamera = true
            map.setCenter(center.clLocation, zoomLevel: viewport.zoom, animated: false)
            context.coordinator.settingCamera = false
        }
        context.coordinator.updateObjects(map)
        context.coordinator.updateCoverage(map)
    }
    static func dismantleUIView(_ map: MLNMapView, coordinator: Coordinator) { map.delegate = nil }

    @MainActor final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
        var parent: OfflineVectorMap
        var settingCamera = false
        var lastObjects: Data?
        init(_ parent: OfflineVectorMap) { self.parent = parent }
        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let map = recognizer.view as? MLNMapView else { return }
            let coordinate = map.convert(recognizer.location(in: map), toCoordinateFrom: map)
            parent.onTap(Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            lastObjects = nil
            updateObjects(mapView)
            updateCoverage(mapView)
        }
        func mapViewRegionIsChanging(_ mapView: MLNMapView) { updateCamera(mapView) }
        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) { updateCamera(mapView) }
        func updateCamera(_ map: MLNMapView) {
            guard !settingCamera else { return }
            let center = Coordinate(latitude: map.centerCoordinate.latitude, longitude: map.centerCoordinate.longitude)
            guard center.isValid else { return }
            var updated = parent.viewport
            updated.center = center.worldPoint
            updated.zoom = map.zoomLevel
            updated.clamp()
            guard
                abs(updated.center.x - parent.viewport.center.x) > 1e-10
                    || abs(updated.center.y - parent.viewport.center.y) > 1e-10
                    || abs(updated.zoom - parent.viewport.zoom) > 0.001
            else { return }
            let previous = parent.viewport
            // UIKit may report camera changes during layout. Publish on the next
            // main-actor turn, and discard updates superseded by a user command.
            Task { @MainActor [updated] in
                guard self.parent.viewport == previous else { return }
                self.parent.viewport = updated
            }
        }
        func updateCoverage(_ map: MLNMapView) {
            for id in ["coverage-outline", "coverage-labels"] {
                map.style?.layer(withIdentifier: id)?.isVisible = parent.showRegionBorders
            }
        }
        func updateObjects(_ map: MLNMapView) {
            guard let source = map.style?.source(withIdentifier: "objects") as? MLNShapeSource else { return }
            var features: [[String: Any]] = []
            func append(_ coordinates: [Coordinate], kind: AnnotationKind, layer: String, title: String) {
                guard !coordinates.isEmpty else { return }
                var points = coordinates.map { [$0.longitude, $0.latitude] }
                if kind == .area, let first = points.first { points.append(first) }
                let geometry: [String: Any] = [
                    "type": kind == .point ? "Point" : (kind == .line ? "LineString" : "Polygon"),
                    "coordinates": kind == .point ? points[0] : (kind == .area ? [points] : points),
                ]
                features.append([
                    "type": "Feature", "properties": ["layer": layer, "name": title], "geometry": geometry,
                ])
            }
            for item in parent.annotations {
                append(item.coordinates, kind: item.kind, layer: item.layer.rawValue, title: item.title)
            }
            if parent.draft.count >= 2 {
                append(parent.draft, kind: .line, layer: parent.activeLayer.rawValue, title: "")
            }
            for point in parent.draft { append([point], kind: .point, layer: parent.activeLayer.rawValue, title: "") }
            if let position = parent.location {
                append(
                    [position.coordinate], kind: .point, layer: "OWN",
                    title: parent.callsign.isEmpty ? (position.source == .manual ? "MANUAL" : "GPS") : parent.callsign)
            }
            guard
                let data = try? JSONSerialization.data(
                    withJSONObject: ["type": "FeatureCollection", "features": features], options: .sortedKeys),
                data != lastObjects,
                let shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue)
            else { return }
            source.shape = shape
            lastObjects = data
        }
    }
}

extension Coordinate {
    fileprivate var clLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
