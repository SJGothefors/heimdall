import XCTest
import ImageIO
@testable import Heimdall

@MainActor
final class HeimdallTests: XCTestCase {
    private func temporaryFiles() throws -> SecureFiles {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return try SecureFiles(root: directory)
    }

    func testProjectionRoundTripAndScreenCoordinates() {
        let cities = [Coordinate(latitude: 59.3293, longitude: 18.0686), Coordinate(latitude: 67.8558, longitude: 20.2253)]
        var viewport = MapViewport()
        viewport.fit(.sweden, size: CGSize(width: 390, height: 600))
        for city in cities {
            let restored = Coordinate(worldPoint: city.worldPoint)
            XCTAssertEqual(restored.latitude, city.latitude, accuracy: 1e-9)
            XCTAssertEqual(restored.longitude, city.longitude, accuracy: 1e-9)
            let screen = viewport.screenPoint(city, size: CGSize(width: 390, height: 600))
            let inverse = viewport.coordinate(at: screen, size: CGSize(width: 390, height: 600))
            XCTAssertEqual(inverse.latitude, city.latitude, accuracy: 1e-9)
        }
    }

    func testBundledMapIsCompleteAndValid() throws {
        let directory = try XCTUnwrap(Bundle.main.resourceURL?.appendingPathComponent("Sweden"))
        let loaded = try MapRepository.read(directory)
        XCTAssertGreaterThan(loaded.package.features.count, 500)
        XCTAssertTrue(loaded.package.places.contains { $0.name == "Stockholm" })
        XCTAssertEqual(loaded.package.elevation.meters.count, 129*257)
        XCTAssertGreaterThan(loaded.photo.count, 100_000)
    }

    func testInvalidGeometryRejected() {
        let outside = MapAnnotation(layer: .red, kind: .point, title: "Test", coordinates: [Coordinate(latitude: 0, longitude: 0)])
        XCTAssertFalse(outside.isValid)
        let incomplete = MapAnnotation(layer: .blue, kind: .area, title: "Test", coordinates: [Coordinate(latitude: 60, longitude: 16)])
        XCTAssertFalse(incomplete.isValid)
        XCTAssertFalse(Coordinate(latitude: .nan, longitude: 16).isValid)
    }

    func testReportPersistsEditsSentStateAndDeletionAcrossLaunches() throws {
        let files = try temporaryFiles()
        let store = LocalStore(files: files)
        try store.load()
        var report = SevenSReport()
        report.stund = "24 sep 2026, 14:35 CEST"
        report.stalle = "Testplats"
        report.styrka = "2"
        report.slag = "Testobjekt"
        report.sysselsattning = "Testobservation"
        report.symbol = "Ej observerat"
        report.sagesman = "Testenhet"
        try store.saveReport(report)
        report.sentAt = Date()
        try store.saveReport(report)
        let reopened = LocalStore(files: files)
        try reopened.load()
        XCTAssertEqual(reopened.reports.count, 1)
        XCTAssertEqual(reopened.reports[0], report)
        XCTAssertEqual(report.completedCount, 7)
        XCTAssertTrue(report.radioText.contains("SYsselsättning".uppercased()))
        try reopened.deleteReport(report.id)
        let afterDelete = LocalStore(files: files)
        try afterDelete.load()
        XCTAssertTrue(afterDelete.reports.isEmpty)
    }

    func testIncompleteReportsExplicitlyMarkMissingFields() {
        var report = SevenSReport()
        XCTAssertFalse(report.isValid)
        report.stalle = "Testplats"
        XCTAssertTrue(report.isValid)
        XCTAssertEqual(report.completedCount, 1)
        XCTAssertTrue(report.radioText.contains("STUND: Ej angivet"))
        report.symbol = String(repeating: "x", count: 2001)
        XCTAssertFalse(report.isValid)
    }

    func testCorruptJournalIsPreservedAndCannotBeOverwritten() throws {
        let files = try temporaryFiles()
        let invalid = Data("{broken}".utf8)
        try SecureFiles.write(invalid, to: files.journalURL)
        let store = LocalStore(files: files)
        XCTAssertThrowsError(try store.load())
        var report = SevenSReport()
        report.stalle = "Test"
        XCTAssertThrowsError(try store.saveReport(report))
        XCTAssertEqual(try Data(contentsOf: files.journalURL), invalid)
    }

    func testIndependentLayersAndProtectedPersistence() throws {
        let files = try temporaryFiles()
        let store = LocalStore(files: files)
        try store.load()
        for layer in TacticalLayer.allCases {
            try store.save(MapAnnotation(layer: layer, kind: .point, title: layer.rawValue, coordinates: [Coordinate(latitude: 60, longitude: 16)]))
        }
        let reopened = LocalStore(files: files)
        try reopened.load()
        XCTAssertEqual(Set(reopened.annotations.map(\.layer)), Set(TacticalLayer.allCases))
        let values = try files.root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testCompleteFileProtectionOnPhysicalDevice() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("The simulator does not expose iOS Data Protection attributes; verify on a physical iPhone.")
        #else
        let files = try temporaryFiles()
        try SecureFiles.write(Data("protection-test".utf8), to: files.journalURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: files.journalURL.path)
        XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .complete)
        #endif
    }

    func testMapImportRejectsSymlink() throws {
        let files = try temporaryFiles()
        let directory = files.root.appendingPathComponent("bad-map")
        try SecureFiles.createDirectory(directory)
        let source = try XCTUnwrap(Bundle.main.resourceURL?.appendingPathComponent("Sweden/map.json"))
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("map.json"), withDestinationURL: source)
        XCTAssertThrowsError(try MapRepository.read(directory))
    }

    func testInvalidElevationGridRejected() throws {
        let directory = try XCTUnwrap(Bundle.main.resourceURL?.appendingPathComponent("Sweden"))
        var package = try MapRepository.read(directory).package
        package.elevation.columns = Int.max
        XCTAssertThrowsError(try package.validate())
    }

    func testMapImportReplacementFailureAndRestore() async throws {
        let files = try temporaryFiles()
        let maps = MapRepository(files: files)
        let bundled = try XCTUnwrap(Bundle.main.resourceURL?.appendingPathComponent("Sweden"))
        try await maps.load()
        try await maps.importDirectory(bundled)
        XCTAssertTrue(maps.isImported)
        let source = files.root.appendingPathComponent("test-source")
        try FileManager.default.copyItem(at: bundled, to: source)
        var replacement = try MapRepository.read(source).package
        replacement.name = "Replacement pack"
        try JSONEncoder().encode(replacement).write(to: source.appendingPathComponent("map.json"))
        try await maps.importDirectory(source)
        XCTAssertEqual(maps.package?.name, "Replacement pack")
        XCTAssertEqual(try MapRepository.read(files.importedMapDirectory).package.name, "Replacement pack")
        try Data("invalid".utf8).write(to: source.appendingPathComponent("map.json"))
        do {
            try await maps.importDirectory(source)
            XCTFail("An invalid map must be rejected")
        } catch {
            XCTAssertEqual(maps.package?.name, "Replacement pack")
            XCTAssertEqual(try MapRepository.read(files.importedMapDirectory).package.name, "Replacement pack")
        }
        try await maps.useBundledMap()
        XCTAssertFalse(maps.isImported)
        XCTAssertEqual(maps.package?.name, "Sweden overview")
    }

    func testMediaSaveThumbnailAndDeletion() async throws {
        let files = try temporaryFiles()
        let store = LocalStore(files: files)
        try store.load()
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48)).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
        }
        let data = try XCTUnwrap(photo.jpegData(compressionQuality: 0.9))
        let vault = MediaVault(files: files)
        let item = try await vault.savePhoto(data)
        try store.addMedia(item)
        XCTAssertTrue(FileManager.default.fileExists(atPath: files.mediaDirectory.appendingPathComponent(item.thumbnailName).path))
        try store.deleteMedia(item)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files.mediaDirectory.appendingPathComponent(item.fileName).path))
        XCTAssertTrue(store.media.isEmpty)
    }
}
