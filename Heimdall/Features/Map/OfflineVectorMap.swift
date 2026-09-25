@preconcurrency import MapLibre
import SwiftUI

struct OfflineVectorMap: UIViewRepresentable {
    let maps: MapRepository
    let photoMode: Bool
    let showRegionBorders: Bool
    @Binding var viewport: MapViewport
    let annotations: [MapAnnotation]
    let visibleLayers: Set<TacticalLayer>
    let draft: [Coordinate]
    let activeLayer: TacticalLayer
    let location: PositionSnapshot?
    let callsign: String
    let onTap: (Coordinate) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MLNMapView {
        MLNNetworkConfiguration.sharedManager.sessionConfiguration = OfflineMapNetwork.configuration()
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
        context.coordinator.updateVisibility(map)
    }
    static func dismantleUIView(_ map: MLNMapView, coordinator: Coordinator) { map.delegate = nil }

    @MainActor final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
        var parent: OfflineVectorMap
        var settingCamera = false
        let overlays = MapOverlayRenderer()
        var lastVisibility: Set<TacticalLayer>?
        var lastCoverage: Bool?
        init(_ parent: OfflineVectorMap) { self.parent = parent }
        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let map = recognizer.view as? MLNMapView else { return }
            let coordinate = map.convert(recognizer.location(in: map), toCoordinateFrom: map)
            parent.onTap(Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            overlays.invalidate()
            lastVisibility = nil
            lastCoverage = nil
            updateObjects(mapView)
            updateVisibility(mapView)
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
        func updateVisibility(_ map: MLNMapView) {
            guard let style = map.style else { return }
            if lastCoverage != parent.showRegionBorders {
                for id in ["coverage-outline", "coverage-labels"] {
                    style.layer(withIdentifier: id)?.isVisible = parent.showRegionBorders
                }
                lastCoverage = parent.showRegionBorders
            }
            if lastVisibility != parent.visibleLayers {
                // The unfinished drawing remains visible, as it did before
                // saved objects and drafts had separate sources.
                for layer in TacticalLayer.allCases {
                    for kind in ["area", "line", "point", "label"] {
                        style.layer(withIdentifier: "objects-\(kind)-\(layer.rawValue)")?.isVisible =
                            parent.visibleLayers.contains(layer)
                    }
                }
                lastVisibility = parent.visibleLayers
            }
        }
        func updateObjects(_ map: MLNMapView) {
            guard let style = map.style,
                MapOverlayRenderer.Source.allCases.allSatisfy({
                    style.source(withIdentifier: $0.rawValue) is MLNShapeSource
                })
            else { return }
            for update in overlays.updates(
                annotations: parent.annotations, draft: parent.draft, layer: parent.activeLayer,
                position: parent.location, callsign: parent.callsign)
            {
                (style.source(withIdentifier: update.source.rawValue) as? MLNShapeSource)?.shape = update.shape
            }
        }
    }
}

extension Coordinate {
    fileprivate var clLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
