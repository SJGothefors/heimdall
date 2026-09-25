import Foundation

/// WGS 84 → UTM/MGRS for the app's Sweden coverage. Grid digits are truncated,
/// never rounded across a square boundary. This deliberately does not implement UPS.
enum MGRS {
    static func string(for coordinate: Coordinate) -> String? {
        guard MapBounds.sweden.contains(coordinate) else { return nil }
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        var zone = Int(floor((lon + 180) / 6)) + 1
        if lat >= 56 && lat < 64 && lon >= 3 && lon < 12 { zone = 32 }
        let phi = lat * .pi / 180
        let lambda = (lon - Double(zone * 6 - 183)) * .pi / 180
        let a = 6_378_137.0
        let e2 = 0.0066943799901413165
        let k = 0.9996
        let ep2 = e2 / (1 - e2)
        let n = a / sqrt(1 - e2 * pow(sin(phi), 2))
        let t = pow(tan(phi), 2)
        let c = ep2 * pow(cos(phi), 2)
        let A = cos(phi) * lambda
        let m =
            a
            * ((1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * pow(e2, 3) / 256) * phi
                - (3 * e2 / 8 + 3 * e2 * e2 / 32 + 45 * pow(e2, 3) / 1024) * sin(2 * phi)
                + (15 * e2 * e2 / 256 + 45 * pow(e2, 3) / 1024) * sin(4 * phi)
                - (35 * pow(e2, 3) / 3072) * sin(6 * phi))
        let east =
            500_000 + k * n
            * (A + (1 - t + c) * pow(A, 3) / 6 + (5 - 18 * t + t * t + 72 * c - 58 * ep2) * pow(A, 5) / 120)
        let north =
            k
            * (m + n * tan(phi)
                * (A * A / 2 + (5 - t + 9 * c + 4 * c * c) * pow(A, 4) / 24
                    + (61 - 58 * t + t * t + 600 * c - 330 * ep2) * pow(A, 6) / 720))
        let bands = Array("CDEFGHJKLMNPQRSTUVWX")
        let columns = [Array("ABCDEFGH"), Array("JKLMNPQR"), Array("STUVWXYZ")]
        let rows = Array("ABCDEFGHJKLMNPQRSTUV")
        let column = Int(floor(east / 100_000)) - 1
        guard (0..<8).contains(column) else { return nil }
        let row = (Int(floor(north / 100_000)) + (zone % 2 == 0 ? 5 : 0)) % 20
        let band = bands[min(19, Int(floor((lat + 80) / 8)))]
        return String(
            format: "%02d%@ %@%@ %05d %05d", zone, String(band),
            String(columns[(zone - 1) % 3][column]), String(rows[row]),
            Int(floor(east)) % 100_000, Int(floor(north)) % 100_000)
    }
}
