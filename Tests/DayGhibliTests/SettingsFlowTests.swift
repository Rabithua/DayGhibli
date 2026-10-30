import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
import WallpaperCore
@testable import DayGhibli

@MainActor
final class SettingsFlowTests: XCTestCase {
    func testSettingsPersistWithoutDownloadingAndLegacyStateKeepsCurrentWallpaper() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let clock = SettingsClock(now: date(hour: 8))
        try writeLegacyState(fixture, changedAt: clock.now)
        let downloader = SettingsDownloader(files: fixture.files)
        let desktop = SettingsDesktop()
        let model = WallpaperModel(catalog: fixture.catalog, directory: fixture.directory,
            downloader: downloader, desktop: desktop, now: { clock.now })

        XCTAssertEqual(model.current, fixture.catalog[0])
        XCTAssertFalse(model.differentWallpapers)
        XCTAssertFalse(model.autoEnabled)
        XCTAssertNil(model.nextAutomaticChange)
        model.differentWallpapers = true
        model.autoEnabled = true

        XCTAssertEqual(model.nextAutomaticChange, date(hour: 9))
        let restored = WallpaperModel(catalog: fixture.catalog, directory: fixture.directory,
            downloader: downloader, desktop: desktop, now: { clock.now })
        XCTAssertTrue(restored.differentWallpapers)
        XCTAssertTrue(restored.autoEnabled)
        XCTAssertEqual(restored.nextAutomaticChange, date(hour: 9))
        XCTAssertEqual(restored.current, fixture.catalog[0])
        XCTAssertEqual(restored.lastChanged, clock.now)
        let requests = await downloader.requests()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(desktop.appliedAssignments.isEmpty)
    }

    func testSharedWallpaperDownloadsOnceAndAssignsSameFileToBothDisplays() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let downloader = SettingsDownloader(files: fixture.files)
        let desktop = SettingsDesktop()
        let model = WallpaperModel(catalog: fixture.catalog, directory: fixture.directory,
            downloader: downloader, desktop: desktop, now: { self.date(hour: 8) })
        model.differentWallpapers = false

        await model.changeNow()

        let requests = await downloader.requests()
        let assignments = try XCTUnwrap(desktop.appliedAssignments.last)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(desktop.appliedAssignments.count, 1)
        XCTAssertEqual(Set(assignments.map(\.displayID)), Set(desktop.displayIDs))
        XCTAssertEqual(assignments.count, 2)
        XCTAssertEqual(Set(assignments.map(\.file)).count, 1)
        XCTAssertEqual(assignments.first?.file, fixture.files[requests[0]])
        XCTAssertNil(model.errorMessage)
    }

    func testIndependentWallpapersDownloadDistinctImagesForBothDisplays() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let downloader = SettingsDownloader(files: fixture.files)
        let desktop = SettingsDesktop()
        let model = WallpaperModel(catalog: fixture.catalog, directory: fixture.directory,
            downloader: downloader, desktop: desktop, now: { self.date(hour: 8) })
        model.differentWallpapers = true

        await model.changeNow()

        let requests = await downloader.requests()
        let assignments = try XCTUnwrap(desktop.appliedAssignments.last)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(Set(requests).count, 2)
        XCTAssertEqual(desktop.appliedAssignments.count, 1)
        XCTAssertEqual(Set(assignments.map(\.displayID)), Set(desktop.displayIDs))
        XCTAssertEqual(assignments.count, 2)
        XCTAssertEqual(Set(assignments.map(\.file)).count, 2)
        XCTAssertEqual(Set(assignments.map(\.file)), Set(requests.compactMap { fixture.files[$0] }))
        XCTAssertNil(model.errorMessage)
    }

    func testSecondDownloadFailureAppliesNothingAndPreservesPreviousSuccess() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let clock = SettingsClock(now: date(hour: 8))
        try writeLegacyState(fixture, changedAt: clock.now)
        let downloader = SettingsDownloader(files: fixture.files, failOnRequest: 2)
        let desktop = SettingsDesktop()
        let model = WallpaperModel(catalog: fixture.catalog, directory: fixture.directory,
            downloader: downloader, desktop: desktop, now: { clock.now })
        model.differentWallpapers = true
        let previousBytes = try Data(contentsOf: fixture.directory.appendingPathComponent("state.json"))

        await model.changeNow()

        let requests = await downloader.requests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(Set(requests).count, 2)
        XCTAssertTrue(desktop.appliedAssignments.isEmpty)
        XCTAssertEqual(model.current, fixture.catalog[0])
        XCTAssertEqual(model.lastChanged, clock.now)
        XCTAssertEqual(try Data(contentsOf: fixture.directory.appendingPathComponent("state.json")), previousBytes)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isBusy)
    }

    func testAutomaticChangeWaitsUntilDueRunsOnceAndPersistsSchedule() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let clock = SettingsClock(now: date(hour: 7))
        let downloader = SettingsDownloader(files: fixture.files)
        let desktop = SettingsDesktop()
        let model = WallpaperModel(catalog: fixture.catalog, directory: fixture.directory,
            downloader: downloader, desktop: desktop, now: { clock.now })

        await model.checkAutomaticChange(at: clock.now)
        var requests = await downloader.requests()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertNil(model.nextAutomaticChange)

        clock.now = date(hour: 8)
        model.autoEnabled = true
        XCTAssertEqual(model.nextAutomaticChange, date(hour: 9))
        clock.now = date(hour: 8, minute: 59)
        await model.checkAutomaticChange(at: clock.now)
        requests = await downloader.requests()
        XCTAssertTrue(requests.isEmpty)

        clock.now = date(hour: 9)
        await model.checkAutomaticChange(at: clock.now)
        await model.checkAutomaticChange(at: clock.now)
        requests = await downloader.requests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(desktop.appliedAssignments.count, 1)
        XCTAssertEqual(model.nextAutomaticChange, date(dayOffset: 1, hour: 9))

        let restored = WallpaperModel(catalog: fixture.catalog, directory: fixture.directory,
            downloader: downloader, desktop: desktop, now: { clock.now })
        XCTAssertTrue(restored.autoEnabled)
        XCTAssertEqual(restored.nextAutomaticChange, date(dayOffset: 1, hour: 9))
        restored.autoEnabled = false
        XCTAssertNil(restored.nextAutomaticChange)
        clock.now = date(dayOffset: 1, hour: 9)
        await restored.checkAutomaticChange(at: clock.now)
        requests = await downloader.requests()
        XCTAssertEqual(requests.count, 1)

        let disabled = WallpaperModel(catalog: fixture.catalog, directory: fixture.directory,
            downloader: downloader, desktop: desktop, now: { clock.now })
        XCTAssertFalse(disabled.autoEnabled)
        XCTAssertNil(disabled.nextAutomaticChange)
    }

    func testFailedAutomaticChangeKeepsDueTimeAndCanRetryAfterFifteenMinutes() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let clock = SettingsClock(now: date(hour: 8))
        let downloader = SettingsDownloader(files: fixture.files, failOnRequest: 1)
        let desktop = SettingsDesktop()
        let model = WallpaperModel(catalog: fixture.catalog, directory: fixture.directory,
            downloader: downloader, desktop: desktop, now: { clock.now })
        model.autoEnabled = true
        let due = try XCTUnwrap(model.nextAutomaticChange)
        clock.now = date(hour: 9)

        await model.checkAutomaticChange(at: clock.now)

        XCTAssertEqual(model.nextAutomaticChange, due)
        XCTAssertTrue(desktop.appliedAssignments.isEmpty)
        XCTAssertNil(model.current)
        XCTAssertNotNil(model.errorMessage)
        clock.now = date(hour: 9, minute: 16)

        await model.checkAutomaticChange(at: clock.now)

        let requests = await downloader.requests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(desktop.appliedAssignments.count, 1)
        XCTAssertNotNil(model.current)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.nextAutomaticChange, date(dayOffset: 1, hour: 9))
    }

    private func date(dayOffset: Int = 0, hour: Int, minute: Int = 0) -> Date {
        let calendar = Calendar.current
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30,
                                                      hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: dayOffset, to: base)!
    }

    private func makeFixture() throws -> SettingsFixture {
        let json = #"[{"id":"totoro001","filmID":"totoro","filmTitle":"龙猫","url":"https://www.ghibli.jp/gallery/totoro001.jpg"},{"id":"totoro002","filmID":"totoro","filmTitle":"龙猫","url":"https://www.ghibli.jp/gallery/totoro002.jpg"},{"id":"chihiro001","filmID":"chihiro","filmTitle":"千与千寻","url":"https://www.ghibli.jp/gallery/chihiro001.jpg"},{"id":"chihiro002","filmID":"chihiro","filmTitle":"千与千寻","url":"https://www.ghibli.jp/gallery/chihiro002.jpg"}]"#
        let catalog = try JSONDecoder().decode([Wallpaper].self, from: Data(json.utf8))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayGhibliSettingsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pixels = Data(repeating: 127, count: 8 * 8 * 3)
        let provider = try XCTUnwrap(CGDataProvider(data: pixels as CFData))
        let image = try XCTUnwrap(CGImage(width: 8, height: 8, bitsPerComponent: 8,
            bitsPerPixel: 24, bytesPerRow: 8 * 3, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes,
            UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let files = try Dictionary(uniqueKeysWithValues: catalog.map { wallpaper in
            let file = directory.appendingPathComponent("\(wallpaper.id).jpg")
            try (bytes as Data).write(to: file)
            return (wallpaper.id, file)
        })
        return SettingsFixture(directory: directory, catalog: catalog, files: files)
    }

    private func writeLegacyState(_ fixture: SettingsFixture, changedAt: Date) throws {
        let image = fixture.catalog[0]
        let current = try JSONSerialization.jsonObject(with: JSONEncoder().encode(image))
        let oldState: [String: Any] = [
            "selectedFilmID": "all", "current": current,
            "currentFile": fixture.files[image.id]!.absoluteString,
            "lastChanged": changedAt.timeIntervalSinceReferenceDate,
            "seen": [image.id], "previousDesktop": []
        ]
        try JSONSerialization.data(withJSONObject: oldState)
            .write(to: fixture.directory.appendingPathComponent("state.json"))
    }
}

private struct SettingsFixture {
    let directory: URL
    let catalog: [Wallpaper]
    let files: [String: URL]

    func cleanUp() { try? FileManager.default.removeItem(at: directory) }
}

@MainActor
private final class SettingsClock {
    var now: Date
    init(now: Date) { self.now = now }
}

private enum SettingsStubError: Error {
    case downloadFailed
}

private actor SettingsDownloader: WallpaperDownloading {
    private let files: [String: URL]
    private let failOnRequest: Int?
    private var requestedIDs: [String] = []

    init(files: [String: URL], failOnRequest: Int? = nil) {
        self.files = files
        self.failOnRequest = failOnRequest
    }

    func download(_ image: Wallpaper) async throws -> URL {
        requestedIDs.append(image.id)
        if requestedIDs.count == failOnRequest { throw SettingsStubError.downloadFailed }
        guard let file = files[image.id] else { throw SettingsStubError.downloadFailed }
        return file
    }

    func requests() -> [String] { requestedIDs }
}

@MainActor
private final class SettingsDesktop: DesktopApplying {
    let displayIDs: [UInt32] = [11, 22]
    private(set) var appliedAssignments: [[DisplayWallpaper]] = []

    func capture() -> [DesktopSnapshot] {
        displayIDs.map { id in
            DesktopSnapshot(displayID: id, url: URL(fileURLWithPath: "/tmp/original-\(id).jpg"),
                            scaling: nil, clipping: nil, fill: nil)
        }
    }

    func apply(file: URL) throws {
        try apply(assignments: displayIDs.map { DisplayWallpaper(displayID: $0, file: file) })
    }

    func apply(assignments: [DisplayWallpaper]) throws {
        appliedAssignments.append(assignments)
    }

    func restore(_ snapshots: [DesktopSnapshot]) throws {}
}
