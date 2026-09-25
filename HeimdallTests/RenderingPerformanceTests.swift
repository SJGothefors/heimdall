import ImageIO
@preconcurrency import MapLibre
import SceneKit
import UIKit
import UniformTypeIdentifiers
import XCTest

@testable import Heimdall

@MainActor final class RenderingPerformanceTests: XCTestCase {
    private let point = Coordinate(latitude: 57.6348, longitude: 18.2948)

    private func annotations(_ count: Int) -> [MapAnnotation] {
        (0..<count).map { index in
            MapAnnotation(
                layer: TacticalLayer.allCases[index % 3], kind: .point, title: "Test \(index)",
                coordinates: [
                    Coordinate(
                        latitude: 57.6 + Double(index % 100) / 1000,
                        longitude: 18.2 + Double(index / 100) / 1000)
                ])
        }
    }

    func testOverlayUpdatesAreIndependentAndUnchangedFramesDoNoWork() throws {
        let renderer = MapOverlayRenderer()
        var saved = annotations(1000)
        var position = PositionSnapshot(coordinate: point, source: .gps, timestamp: .now, accuracy: 10)
        func update(_ draft: [Coordinate] = [], callsign: String = "") -> [MapOverlayRenderer.Update] {
            renderer.updates(annotations: saved, draft: draft, layer: .blue, position: position, callsign: callsign)
        }
        XCTAssertEqual(Set(update().map(\.source)), Set(MapOverlayRenderer.Source.allCases))
        for _ in 0..<60 { XCTAssertTrue(update().isEmpty) }
        position.timestamp = .now
        position.accuracy = 5
        XCTAssertTrue(update().isEmpty, "Nonvisual GPS metadata must not rebuild map geometry")
        position.coordinate.longitude += 0.0001
        XCTAssertEqual(update().map(\.source), [.position])
        XCTAssertEqual(update([point]).map(\.source), [.draft])
        XCTAssertEqual(update([point], callsign: "TEST").map(\.source), [.position])
        saved[0].title = "Edited"
        XCTAssertEqual(update([point], callsign: "TEST").map(\.source), [.objects])
        let cleared = renderer.updates(annotations: [], draft: [], layer: .blue, position: nil, callsign: "")
        XCTAssertEqual(cleared.count, 3)
        XCTAssertTrue(cleared.allSatisfy { $0.shape.shapes.isEmpty })
        renderer.invalidate()
        XCTAssertEqual(renderer.updates(annotations: [], draft: [], layer: .blue, position: nil, callsign: "").count, 3)
    }

    func testNativeFeaturesPreserveGeometryLabelsAndDraftVertices() throws {
        let points = [
            point, Coordinate(latitude: 57.64, longitude: 18.3), Coordinate(latitude: 57.65, longitude: 18.29),
        ]
        let saved = [
            MapAnnotation(layer: .blue, kind: .point, title: "Point", coordinates: [point]),
            MapAnnotation(layer: .red, kind: .line, title: "Line", coordinates: Array(points.prefix(2))),
            MapAnnotation(layer: .tac, kind: .area, title: "Area", coordinates: points),
        ]
        let updates = MapOverlayRenderer().updates(
            annotations: saved, draft: points, layer: .red,
            position: PositionSnapshot(coordinate: point, source: .manual, timestamp: .now), callsign: "")
        let objects = try XCTUnwrap(updates.first { $0.source == .objects }?.shape)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: objects.geoJSONData(usingEncoding: String.Encoding.utf8.rawValue))
                as? [String: Any])
        let features = try XCTUnwrap(json["features"] as? [[String: Any]])
        XCTAssertEqual(features.count, 3)
        let geometry = try features.map { try XCTUnwrap($0["geometry"] as? [String: Any]) }
        XCTAssertEqual(geometry.compactMap { $0["type"] as? String }, ["Point", "LineString", "Polygon"])
        let ring = try XCTUnwrap((geometry[2]["coordinates"] as? [[[Double]]])?.first)
        XCTAssertEqual(ring.count, 4)
        XCTAssertEqual(ring.first, ring.last)
        XCTAssertEqual(ring.first, [point.longitude, point.latitude])
        XCTAssertEqual(objects.shapes.map { $0.attributes["name"] as? String }, ["Point", "Line", "Area"])
        XCTAssertEqual(objects.shapes.map { $0.attributes["layer"] as? String }, ["BLUE", "RED", "TAC"])
        XCTAssertEqual(updates.first { $0.source == .draft }?.shape.shapes.count, 4)
        XCTAssertEqual(
            updates.first { $0.source == .position }?.shape.shapes.first?.attributes["name"] as? String, "MANUAL")
    }

    func testOverlayStyleHasSeparateSourcesAndUniqueLayerIDs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let maps = MapRepository(files: try SecureFiles(root: root))
        try await maps.load()
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(OfflineMapStyle.json(maps: maps, photo: false).utf8))
                as? [String: Any])
        let sources = try XCTUnwrap(json["sources"] as? [String: Any])
        for source in MapOverlayRenderer.Source.allCases { XCTAssertNotNil(sources[source.rawValue]) }
        let layers = try XCTUnwrap(json["layers"] as? [[String: Any]])
        let ids = layers.compactMap { $0["id"] as? String }
        XCTAssertEqual(ids.count, Set(ids).count)
        for source in ["objects", "draft"] {
            for layer in TacticalLayer.allCases {
                for kind in ["point", "line", "area", "label"] {
                    XCTAssertTrue(ids.contains("\(source)-\(kind)-\(layer.rawValue)"))
                }
            }
        }
    }

    func testTerrainOverlayChangesKeepMeshTextureAndCamera() throws {
        let url = try XCTUnwrap(Bundle.main.resourceURL?.appendingPathComponent("Sweden"))
        let loaded = try MapRepository.read(url)
        let terrain = TerrainScene(package: loaded.package, photo: UIImage(data: loaded.photo))
        let geometry = try XCTUnwrap(terrain.ground.geometry)
        let material = try XCTUnwrap(geometry.firstMaterial)
        XCTAssertEqual(geometry.sources(for: .vertex).first?.vectorCount, 129 * 257)
        terrain.camera.position = SCNVector3(1, 2, 3)
        let saved = annotations(10)
        terrain.update(annotations: saved, coverage: [])
        XCTAssertEqual(terrain.annotationNode.childNodes.count, 10)
        let annotationNode = try XCTUnwrap(terrain.annotationNode.childNodes.first)
        let region = RegionManifest(
            version: 1, id: "test", name: "Test", schema: "protomaps-v4",
            bounds: .sweden, focus: point, sourceDate: "", attribution: "Test", sourceURL: "",
            sha256: String(repeating: "a", count: 64))
        terrain.update(annotations: saved, coverage: [region])
        XCTAssertTrue(terrain.annotationNode.childNodes.first === annotationNode)
        XCTAssertEqual(terrain.coverageNode.childNodes.count, 1)
        terrain.update(annotations: [], coverage: [])
        XCTAssertTrue(terrain.annotationNode.childNodes.isEmpty)
        XCTAssertTrue(terrain.coverageNode.childNodes.isEmpty)
        XCTAssertTrue(terrain.ground.geometry === geometry)
        XCTAssertTrue(terrain.ground.geometry?.firstMaterial === material)
        XCTAssertEqual(terrain.camera.position.x, 1)
        XCTAssertEqual(terrain.camera.position.y, 2)
        XCTAssertEqual(terrain.camera.position.z, 3)
    }

    func testPhotoDecodeBoundsMemoryNormalizesOrientationAndPreservesFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 4032, height: 3024), format: format).image {
            context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4032, height: 3024))
        }
        let encoded = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(encoded, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(
            destination, try XCTUnwrap(original.cgImage), [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        try SecureFiles.write(encoded as Data, to: url)
        let thumbnail = try await LocalImageLoader.shared.image(at: url, maximumPixelSize: 1008)
        XCTAssertEqual(thumbnail.width, 756)
        XCTAssertEqual(thumbnail.height, 1008)
        XCTAssertLessThanOrEqual(thumbnail.bytesPerRow * thumbnail.height, 4 * 1024 * 1024)
        XCTAssertEqual(try Data(contentsOf: url), encoded as Data)
        let cancelled = Task { try await LocalImageLoader.shared.image(at: url, maximumPixelSize: 500) }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            XCTFail("Cancelled image loads must not publish pixels")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        do {
            _ = try await LocalImageLoader.shared.image(
                at: XCTUnwrap(URL(string: "https://example.invalid/photo.jpg")), maximumPixelSize: 500)
            XCTFail("Image loading must remain local")
        } catch { XCTAssertTrue(error is AppError) }
    }

    func testOverlayUpdateBenchmark() throws {
        let saved = annotations(2000)
        let renderer = MapOverlayRenderer()
        _ = renderer.updates(annotations: saved, draft: [], layer: .blue, position: nil, callsign: "")
        let iterations = 40
        // Keep the former per-frame JSON path here as a reproducible baseline.
        // It omits native parsing, just as the old cache did for unchanged data.
        func previousFrame() throws -> Data {
            let features: [[String: Any]] = saved.map { item in
                [
                    "type": "Feature", "properties": ["layer": item.layer.rawValue, "name": item.title],
                    "geometry": [
                        "type": "Point", "coordinates": [item.coordinates[0].longitude, item.coordinates[0].latitude],
                    ],
                ]
            }
            return try JSONSerialization.data(
                withJSONObject: ["type": "FeatureCollection", "features": features], options: .sortedKeys)
        }
        let oldStart = CFAbsoluteTimeGetCurrent()
        var totalBytes = 0
        for _ in 0..<iterations { totalBytes += try autoreleasepool { try previousFrame().count } }
        let oldMilliseconds = (CFAbsoluteTimeGetCurrent() - oldStart) * 1000 / Double(iterations)
        let newStart = CFAbsoluteTimeGetCurrent()
        var updates = 0
        for _ in 0..<iterations {
            updates += renderer.updates(annotations: saved, draft: [], layer: .blue, position: nil, callsign: "").count
        }
        let newMilliseconds = (CFAbsoluteTimeGetCurrent() - newStart) * 1000 / Double(iterations)
        XCTAssertGreaterThan(totalBytes, 0)
        XCTAssertEqual(updates, 0)
        print(
            String(
                format: "PERF overlay 2000 points: former %.3f ms/update; cached %.5f ms/update (%d iterations)",
                oldMilliseconds, newMilliseconds, iterations))
    }
}
