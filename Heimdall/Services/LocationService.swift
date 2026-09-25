import CoreLocation
import Observation

@MainActor @Observable
final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private(set) var fix: CLLocation?
    private(set) var message = "Location is off"
    private(set) var isEnabled = false
    private let manager = CLLocationManager()
    var manualPosition: PositionSnapshot?

    var currentPosition: PositionSnapshot? {
        if let coordinate = freshCoordinate, MapBounds.sweden.contains(coordinate), let fix {
            return PositionSnapshot(coordinate: coordinate, source: .gps, timestamp: fix.timestamp, accuracy: fix.horizontalAccuracy)
        }
        return isEnabled ? nil : manualPosition
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
    }

    var freshCoordinate: Coordinate? {
        guard isEnabled, let fix, fix.horizontalAccuracy >= 0,
              abs(fix.timestamp.timeIntervalSinceNow) < 30 else { return nil }
        return Coordinate(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
    }

    func enable() {
        isEnabled = true
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else { startIfAllowed() }
    }

    func stop() {
        manager.stopUpdatingLocation()
        isEnabled = false
        fix = nil
        message = "Location is off"
    }

    private func startIfAllowed() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if isEnabled { message = "Acquiring location…"; manager.startUpdatingLocation() }
        case .denied, .restricted:
            isEnabled = false
            message = "Location permission is off in Settings"
        default: break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { startIfAllowed() }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isEnabled, let latest = locations.last, latest.horizontalAccuracy >= 0,
              abs(latest.timestamp.timeIntervalSinceNow) < 30 else { return }
        fix = latest
        message = "±\(Int(latest.horizontalAccuracy)) m · GPS"
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        message = "Location unavailable · move to open sky"
        fix = nil
    }
}
