import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
import WallpaperCore
@testable import DayGhibli

@MainActor
final class ManualFlowTests: XCTestCase {
    func testInitializationAndFilmSelectionDoNotDownloadOrApply() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = try fixtureCatalog()
        let events = EventLog()
        let downloader = StubDownloader(files: [:], events: events)
        let desktop = StubDesktop(events: events)
        let model = WallpaperModel(catalog: catalog, directory: directory,
                                   downloader: downloader, desktop: desktop)

        model.selectedFilmID = "totoro"

        let requests = await downloader.requests()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(events.snapshot().isEmpty)
        XCTAssertNil(model.current)
        XCTAssertNil(model.lastChanged)
        XCTAssertEqual(model.imageCount, 1)
        XCTAssertEqual(model.films.map(\.title), ["全部作品", "龙猫", "千与千寻"])
    }

    func testManualChangeDownloadsBeforeApplyingPersistsAndExcludesCurrent() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = try fixtureCatalog()
        let files = try fixtureFiles(catalog, in: directory)
        let events = EventLog()
        let downloader = StubDownloader(files: files, events: events)
        let desktop = StubDesktop(events: events)
        let model = WallpaperModel(catalog: catalog, directory: directory,
                                   downloader: downloader, desktop: desktop)

        await model.changeNow()

        let first = try XCTUnwrap(model.current)
        XCTAssertNotNil(model.lastChanged)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.canRevert)
        XCTAssertEqual(events.snapshot(), ["download:\(first.id)", "capture",
                                           "apply:\(first.id).jpg"])
        let saved = try savedState(in: directory)
        XCTAssertEqual((saved["current"] as? [String: Any])?["id"] as? String, first.id)
        XCTAssertEqual(saved["currentFile"] as? String, files[first.id]?.absoluteString)
        let restored = WallpaperModel(catalog: catalog, directory: directory,
                                      downloader: downloader, desktop: desktop)
        XCTAssertEqual(restored.current, first)
        XCTAssertEqual(restored.lastChanged, model.lastChanged)

        await model.changeNow()

        let second = try XCTUnwrap(model.current)
        XCTAssertNotEqual(second.id, first.id)
        let requests = await downloader.requests()
        XCTAssertEqual(requests, [first.id, second.id])
        XCTAssertEqual(desktop.successfulFiles, [files[first.id]!, files[second.id]!])
        XCTAssertEqual(events.snapshot(), ["download:\(first.id)", "capture",
                                           "apply:\(first.id).jpg",
                                           "download:\(second.id)", "capture",
                                           "apply:\(second.id).jpg"])
        XCTAssertFalse(model.isBusy)
    }

    func testDownloadFailureDoesNotApplyAndPreservesCurrentState() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = try fixtureCatalog()
        let events = EventLog()
        let downloader = StubDownloader(files: try fixtureFiles(catalog, in: directory), events: events)
        let desktop = StubDesktop(events: events)
        let model = WallpaperModel(catalog: catalog, directory: directory,
                                   downloader: downloader, desktop: desktop)
        await model.changeNow()
        let previous = try XCTUnwrap(model.current)
        let previousDate = model.lastChanged
        let previousSaved = try Data(contentsOf: directory.appendingPathComponent("state.json"))
        let previousEvents = events.snapshot()
        await downloader.setFailure(true)

        await model.changeNow()

        XCTAssertEqual(model.current, previous)
        XCTAssertEqual(model.lastChanged, previousDate)
        XCTAssertEqual(desktop.successfulFiles.count, 1)
        XCTAssertEqual(events.snapshot().dropLast(), previousEvents[...])
        XCTAssertTrue(try XCTUnwrap(events.snapshot().last).hasPrefix("download:"))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("state.json")), previousSaved)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isBusy)
    }

    func testDesktopFailureDoesNotCommitNewSuccessState() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = try fixtureCatalog()
        let events = EventLog()
        let downloader = StubDownloader(files: try fixtureFiles(catalog, in: directory), events: events)
        let desktop = StubDesktop(events: events)
        let model = WallpaperModel(catalog: catalog, directory: directory,
                                   downloader: downloader, desktop: desktop)
        await model.changeNow()
        let previous = try XCTUnwrap(model.current)
        let previousDate = model.lastChanged
        let previousSaved = try Data(contentsOf: directory.appendingPathComponent("state.json"))
        desktop.shouldFail = true

        await model.changeNow()

        XCTAssertEqual(model.current, previous)
        XCTAssertEqual(model.lastChanged, previousDate)
        XCTAssertEqual(desktop.successfulFiles.count, 1)
        XCTAssertEqual(desktop.applyAttempts, 2)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("state.json")), previousSaved)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isBusy)
    }

    func testJPEGValidationAcceptsCompleteImageAndRejectsTruncation() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let complete = directory.appendingPathComponent("complete.jpg")
        let truncated = directory.appendingPathComponent("truncated.jpg")
        let data = try jpegData()
        try data.write(to: complete)
        try data.dropLast(2).write(to: truncated)

        XCTAssertTrue(ImageStore.isImage(at: complete))
        XCTAssertFalse(ImageStore.isImage(at: truncated))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayGhibliTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func fixtureCatalog() throws -> [Wallpaper] {
        let json = #"[{"id":"totoro001","filmID":"totoro","filmTitle":"龙猫","url":"https://www.ghibli.jp/gallery/totoro001.jpg"},{"id":"chihiro001","filmID":"chihiro","filmTitle":"千与千寻","url":"https://www.ghibli.jp/gallery/chihiro001.jpg"}]"#
        return try JSONDecoder().decode([Wallpaper].self, from: Data(json.utf8))
    }

    private func fixtureFiles(_ catalog: [Wallpaper], in directory: URL) throws -> [String: URL] {
        let bytes = try jpegData()
        return try Dictionary(uniqueKeysWithValues: catalog.map { image in
            let file = directory.appendingPathComponent("\(image.id).jpg")
            try bytes.write(to: file)
            return (image.id, file)
        })
    }

    private func savedState(in directory: URL) throws -> [String: Any] {
        let bytes = try Data(contentsOf: directory.appendingPathComponent("state.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }

    private func jpegData() throws -> Data {
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
        return bytes as Data
    }
}

private enum StubError: Error {
    case requestedFailure
}

private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func append(_ entry: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}

private actor StubDownloader: WallpaperDownloading {
    private let files: [String: URL]
    private let events: EventLog
    private var requested: [String] = []
    private var shouldFail = false

    init(files: [String: URL], events: EventLog) {
        self.files = files
        self.events = events
    }

    func download(_ image: Wallpaper) async throws -> URL {
        requested.append(image.id)
        events.append("download:\(image.id)")
        if shouldFail { throw StubError.requestedFailure }
        guard let file = files[image.id] else { throw StubError.requestedFailure }
        return file
    }

    func setFailure(_ value: Bool) { shouldFail = value }
    func requests() -> [String] { requested }
}

@MainActor
private final class StubDesktop: DesktopApplying {
    let events: EventLog
    var shouldFail = false
    private(set) var successfulFiles: [URL] = []
    private(set) var applyAttempts = 0

    init(events: EventLog) { self.events = events }

    func capture() -> [DesktopSnapshot] {
        events.append("capture")
        return [DesktopSnapshot(displayID: 1, url: URL(fileURLWithPath: "/tmp/original-wallpaper.jpg"),
                                scaling: nil, clipping: nil, fill: nil)]
    }

    func apply(file: URL) throws {
        events.append("apply:\(file.lastPathComponent)")
        applyAttempts += 1
        if shouldFail { throw StubError.requestedFailure }
        successfulFiles.append(file)
    }

    func restore(_ snapshots: [DesktopSnapshot]) throws {}
}
