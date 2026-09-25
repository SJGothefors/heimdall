import XCTest

@testable import Heimdall

@MainActor final class OfflinePolicyTests: XCTestCase {
    func testMapSessionRejectsRemoteRequests() async throws {
        let configuration = OfflineMapNetwork.configuration()
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        for scheme in ["http", "https", "HTTPS"] {
            let url = try XCTUnwrap(URL(string: "\(scheme)://offline-policy-test.invalid/map.json"))
            do {
                _ = try await session.data(from: url)
                XCTFail("Remote map requests must fail closed")
            } catch {
                XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
            }
        }
        XCTAssertFalse(
            OfflineMapProtocol.canInit(with: URLRequest(url: URL(fileURLWithPath: "/local/map.json"))))
    }

    func testMapStylesOnlyReferenceLocalResources() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let maps = MapRepository(files: try SecureFiles(root: root))
        try await maps.load()
        for photo in [false, true] {
            let style = try XCTUnwrap(
                JSONSerialization.jsonObject(
                    with: Data(OfflineMapStyle.json(maps: maps, photo: photo).utf8)) as? [String: Any])
            let glyphs = try XCTUnwrap(style["glyphs"] as? String)
            XCTAssertTrue(glyphs.hasPrefix("file://"))
            let sources = try XCTUnwrap(style["sources"] as? [String: [String: Any]])
            for source in sources.values {
                for key in ["url", "data"] {
                    if let resource = source[key] as? String {
                        XCTAssertTrue(
                            resource.hasPrefix("file://") || resource.hasPrefix("pmtiles://file://"), resource)
                    }
                }
            }
            XCTAssertNil(style["sprite"])
        }
    }

    func testImportKeepsValidatedSnapshotAndRejectsChangedCatalogEntry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = try SecureFiles(root: root)
        let maps = MapRepository(files: files)
        try await maps.load()
        let bundled = try XCTUnwrap(maps.regions.first { $0.id == "gotland" })
        let source = root.appendingPathComponent("selected.zip")
        try FileManager.default.copyItem(at: bundled.archiveURL, to: source)
        try await maps.importRegion(source)
        let imported = try XCTUnwrap(maps.regions.first { $0.id == "gotland" })
        XCTAssertFalse(imported.bundled)
        XCTAssertEqual(try Data(contentsOf: source), try Data(contentsOf: imported.archiveURL))
        try Data("changed provider file".utf8).write(to: source)
        XCTAssertEqual(try RegionPacks.inspect(imported.archiveURL).manifest, bundled.manifest)

        var staleManifest = imported.manifest
        staleManifest.id = "changed-region"
        let stale = RegionPack(
            manifest: staleManifest, archiveURL: imported.archiveURL, byteCount: imported.byteCount,
            bundled: false)
        do {
            try await maps.loadRegion(stale)
            XCTFail("A changed manifest must not be installed under the old path")
        } catch {
            XCTAssertEqual(maps.loadedRegions.map(\.id), ["gotland"])
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: maps.directory(for: staleManifest).path))
        }
    }
}
