import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
import WallpaperCore
@testable import DayGhibli

@MainActor
final class RetentionFlowTests: XCTestCase {
    func testIndependentChangesRetainOnlyCurrentAndPreviousForEachDisplay() async throws {
        let fixture = try fixture()
        defer { fixture.cleanUp() }
        let downloader = RetentionDownloader(directory: fixture.directory, bytes: fixture.jpeg)
        let desktop = RetentionDesktop(files: fixture.initialFiles)
        let model = makeModel(fixture, downloader: downloader, desktop: desktop)
        model.differentWallpapers = true

        await model.changeNow()
        let first = try XCTUnwrap(desktop.assignments.last)
        await model.changeNow()
        let second = try XCTUnwrap(desktop.assignments.last)
        var prunes = await downloader.pruneRequests()
        XCTAssertEqual(prunes.count, 2)
        XCTAssertEqual(prunes.last, Set((first + second).map(\.file)))

        await model.changeNow()
        let third = try XCTUnwrap(desktop.assignments.last)
        prunes = await downloader.pruneRequests()
        let expected = Set((second + third).map(\.file))
        XCTAssertEqual(prunes.count, 3)
        XCTAssertEqual(expected.count, 4)
        XCTAssertEqual(prunes.last, expected)
        XCTAssertTrue(expected.isDisjoint(with: Set(first.map(\.file))))
        let ledger = try readLedger(fixture)
        XCTAssertEqual(ledger.count, 2)
        for assignment in third {
            let entry = try XCTUnwrap(ledger.first { $0.displayID == assignment.displayID })
            XCTAssertEqual(entry.current, assignment.file)
            XCTAssertEqual(entry.previous, second.first { $0.displayID == assignment.displayID }?.file)
        }
        XCTAssertNil(model.errorMessage)
    }

    func testSharedWallpapersDeduplicateRetentionAndRestoreSwapsCurrentAndPrevious() async throws {
        let fixture = try fixture(sharedInitialWallpaper: true)
        defer { fixture.cleanUp() }
        let downloader = RetentionDownloader(directory: fixture.directory, bytes: fixture.jpeg)
        let desktop = RetentionDesktop(files: fixture.initialFiles)
        let model = makeModel(fixture, downloader: downloader, desktop: desktop)

        await model.changeNow()
        let first = try XCTUnwrap(desktop.assignments.last?.first?.file)
        await model.changeNow()
        let second = try XCTUnwrap(desktop.assignments.last?.first?.file)
        var prunes = await downloader.pruneRequests()
        XCTAssertTrue(prunes.allSatisfy { $0.count <= 2 })
        XCTAssertEqual(prunes.last, Set([first, second]))

        await model.restorePreviousWallpaper()

        prunes = await downloader.pruneRequests()
        XCTAssertEqual(prunes.count, 3)
        XCTAssertEqual(prunes.last, Set([first, second]))
        XCTAssertTrue(prunes.allSatisfy { $0.count <= 2 })
        XCTAssertEqual(Set(desktop.files.values), Set([first]))
        let ledger = try readLedger(fixture)
        XCTAssertEqual(ledger.count, 2)
        XCTAssertTrue(ledger.allSatisfy { $0.current == first && $0.previous == second })
        XCTAssertNil(model.errorMessage)
    }

    func testDisconnectedDisplayKeepsItsCurrentAndPreviousProtected() async throws {
        let fixture = try fixture()
        defer { fixture.cleanUp() }
        let downloader = RetentionDownloader(directory: fixture.directory, bytes: fixture.jpeg)
        let desktop = RetentionDesktop(files: fixture.initialFiles)
        let model = makeModel(fixture, downloader: downloader, desktop: desktop)
        model.differentWallpapers = true
        await model.changeNow()
        await model.changeNow()
        let before = try readLedger(fixture)
        let disconnected = try XCTUnwrap(before.first { $0.displayID == 22 })
        let connected = try XCTUnwrap(before.first { $0.displayID == 11 })
        desktop.displayIDs = [11]

        await model.changeNow()

        let ledger = try readLedger(fixture)
        XCTAssertEqual(ledger.count, 2)
        XCTAssertEqual(ledger.first { $0.displayID == 22 }, disconnected)
        let newConnected = try XCTUnwrap(ledger.first { $0.displayID == 11 })
        XCTAssertEqual(newConnected.previous, connected.current)
        let pruning = await downloader.pruneRequests()
        let protected = try XCTUnwrap(pruning.last)
        let expected = Set([newConnected.current, connected.current, disconnected.current]
            + [disconnected.previous].compactMap { $0 })
        XCTAssertEqual(protected, expected)
        XCTAssertTrue(protected.contains(disconnected.current))
        XCTAssertTrue(protected.contains(try XCTUnwrap(disconnected.previous)))
        XCTAssertNil(model.errorMessage)
    }

    func testDownloadAndApplyFailuresDoNotPruneOrUpdateLedger() async throws {
        let fixture = try fixture()
        defer { fixture.cleanUp() }
        let downloader = RetentionDownloader(directory: fixture.directory, bytes: fixture.jpeg)
        let desktop = RetentionDesktop(files: fixture.initialFiles)
        let model = makeModel(fixture, downloader: downloader, desktop: desktop)
        model.differentWallpapers = true
        await model.changeNow()
        let ledger = try readLedger(fixture)
        let previousImage = model.current
        let previousDate = model.lastChanged
        let beforePrunes = await downloader.pruneRequests()
        let completedDownloads = await downloader.requestCount()
        await downloader.setFailureOnRequest(completedDownloads + 1)

        await model.changeNow()

        var afterPrunes = await downloader.pruneRequests()
        XCTAssertEqual(afterPrunes, beforePrunes)
        XCTAssertEqual(try readLedger(fixture), ledger)
        XCTAssertEqual(model.current, previousImage)
        XCTAssertEqual(model.lastChanged, previousDate)
        XCTAssertEqual(desktop.assignments.count, 1)
        XCTAssertNotNil(model.errorMessage)
        await downloader.setFailureOnRequest(nil)
        desktop.shouldFail = true

        await model.changeNow()

        afterPrunes = await downloader.pruneRequests()
        XCTAssertEqual(afterPrunes, beforePrunes)
        XCTAssertEqual(try readLedger(fixture), ledger)
        XCTAssertEqual(model.current, previousImage)
        XCTAssertEqual(model.lastChanged, previousDate)
        XCTAssertEqual(desktop.assignments.count, 1)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isBusy)
    }

    func testLegacyStartupMigrationPinsActualCurrentAndPreviousForBothDisplaysWithoutDownload() async throws {
        let fixture = try fixture()
        defer { fixture.cleanUp() }
        let previous = fixture.initialFiles.map { displayID, _ in
            DesktopSnapshot(displayID: displayID,
                url: fixture.directory.appendingPathComponent("legacy-previous-\(displayID).jpg"),
                scaling: nil, clipping: nil, fill: nil)
        }
        let encodedImage = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture.catalog[0]))
        let encodedPrevious = try JSONSerialization.jsonObject(with: JSONEncoder().encode(previous))
        let oldState: [String: Any] = [
            "selectedFilmID": "all", "current": encodedImage,
            "currentFile": fixture.initialFiles[11]!.absoluteString,
            "seen": [fixture.catalog[0].id], "previousDesktop": encodedPrevious
        ]
        try JSONSerialization.data(withJSONObject: oldState)
            .write(to: fixture.directory.appendingPathComponent("state.json"))
        let downloader = RetentionDownloader(directory: fixture.directory, bytes: fixture.jpeg)
        let desktop = RetentionDesktop(files: fixture.initialFiles)
        let model = makeModel(fixture, downloader: downloader, desktop: desktop)

        await model.cleanUpImages()

        let requests = await downloader.requestCount()
        let prunes = await downloader.pruneRequests()
        XCTAssertEqual(requests, 0)
        XCTAssertTrue(desktop.assignments.isEmpty)
        XCTAssertEqual(prunes.count, 1)
        XCTAssertEqual(prunes.last, Set(Array(fixture.initialFiles.values) + previous.map(\.url)))
        let ledger = try readLedger(fixture)
        XCTAssertEqual(ledger.count, 2)
        for entry in ledger {
            XCTAssertEqual(entry.current, fixture.initialFiles[entry.displayID])
            XCTAssertEqual(entry.previous, previous.first { $0.displayID == entry.displayID }?.url)
        }
        XCTAssertEqual(model.current, fixture.catalog[0])
        XCTAssertNil(model.errorMessage)
    }

    func testCleanupSaveFailureDoesNotPrune() async throws {
        let fixture = try fixture()
        defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(at: fixture.directory.appendingPathComponent("state.json"),
                                                withIntermediateDirectories: false)
        let downloader = RetentionDownloader(directory: fixture.directory, bytes: fixture.jpeg)
        let desktop = RetentionDesktop(files: fixture.initialFiles)
        let model = makeModel(fixture, downloader: downloader, desktop: desktop)

        await model.cleanUpImages()

        let requests = await downloader.requestCount()
        let prunes = await downloader.pruneRequests()
        XCTAssertEqual(requests, 0)
        XCTAssertTrue(prunes.isEmpty)
        XCTAssertNotNil(model.errorMessage)
    }

    private func makeModel(_ fixture: RetentionFixture, downloader: RetentionDownloader,
                           desktop: RetentionDesktop) -> WallpaperModel {
        WallpaperModel(catalog: fixture.catalog, directory: fixture.directory,
            downloader: downloader, desktop: desktop, loginItems: RetentionLoginItems())
    }

    private func readLedger(_ fixture: RetentionFixture) throws -> [RetentionRecord] {
        let data = try Data(contentsOf: fixture.directory.appendingPathComponent("state.json"))
        return try JSONDecoder().decode(RetentionState.self, from: data).displayHistory
    }

    private func fixture(sharedInitialWallpaper: Bool = false) throws -> RetentionFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayGhibliRetentionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = #"[{"id":"totoro001","filmID":"totoro","filmTitle":"龙猫","url":"https://www.ghibli.jp/gallery/totoro001.jpg"},{"id":"totoro002","filmID":"totoro","filmTitle":"龙猫","url":"https://www.ghibli.jp/gallery/totoro002.jpg"},{"id":"totoro003","filmID":"totoro","filmTitle":"龙猫","url":"https://www.ghibli.jp/gallery/totoro003.jpg"},{"id":"totoro004","filmID":"totoro","filmTitle":"龙猫","url":"https://www.ghibli.jp/gallery/totoro004.jpg"}]"#
        let catalog = try JSONDecoder().decode([Wallpaper].self, from: Data(json.utf8))
        let jpeg = try jpegData()
        let first = directory.appendingPathComponent("original-11.jpg")
        let second = sharedInitialWallpaper ? first : directory.appendingPathComponent("original-22.jpg")
        try jpeg.write(to: first)
        if second != first { try jpeg.write(to: second) }
        return RetentionFixture(directory: directory, catalog: catalog, jpeg: jpeg,
                                initialFiles: [11: first, 22: second])
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

private struct RetentionFixture {
    let directory: URL
    let catalog: [Wallpaper]
    let jpeg: Data
    let initialFiles: [UInt32: URL]
    func cleanUp() { try? FileManager.default.removeItem(at: directory) }
}

private struct RetentionRecord: Decodable, Equatable {
    let displayID: UInt32
    let current: URL
    let previous: URL?
}

private struct RetentionState: Decodable {
    let displayHistory: [RetentionRecord]
}

private enum RetentionStubError: Error {
    case requestedFailure
}

private actor RetentionDownloader: WallpaperDownloading {
    private let directory: URL
    private let bytes: Data
    private var requests = 0
    private var failureOnRequest: Int?
    private var pruning: [Set<URL>] = []

    init(directory: URL, bytes: Data) {
        self.directory = directory
        self.bytes = bytes
    }

    func download(_ image: Wallpaper) async throws -> URL {
        requests += 1
        if requests == failureOnRequest { throw RetentionStubError.requestedFailure }
        let file = directory.appendingPathComponent("download-\(requests)-\(image.id).jpg")
        try bytes.write(to: file)
        return file
    }

    func prune(keeping urls: Set<URL>) async throws { pruning.append(urls) }
    func requestCount() -> Int { requests }
    func pruneRequests() -> [Set<URL>] { pruning }
    func setFailureOnRequest(_ request: Int?) { failureOnRequest = request }
}

@MainActor
private final class RetentionDesktop: DesktopApplying {
    var displayIDs: [UInt32] = [11, 22]
    private(set) var files: [UInt32: URL]
    private(set) var assignments: [[DisplayWallpaper]] = []
    var shouldFail = false

    init(files: [UInt32: URL]) { self.files = files }

    func capture() -> [DesktopSnapshot] {
        displayIDs.compactMap { id in
            files[id].map {
                DesktopSnapshot(displayID: id, url: $0, scaling: nil, clipping: nil, fill: nil)
            }
        }
    }

    func apply(file: URL) throws {
        try apply(assignments: displayIDs.map { DisplayWallpaper(displayID: $0, file: file) })
    }

    func apply(assignments newAssignments: [DisplayWallpaper]) throws {
        if shouldFail { throw RetentionStubError.requestedFailure }
        assignments.append(newAssignments)
        for assignment in newAssignments { files[assignment.displayID] = assignment.file }
    }

    func restore(_ snapshots: [DesktopSnapshot]) throws {
        if shouldFail { throw RetentionStubError.requestedFailure }
        for snapshot in snapshots where displayIDs.contains(snapshot.displayID) {
            files[snapshot.displayID] = snapshot.url
        }
    }
}

@MainActor
private struct RetentionLoginItems: LoginItemManaging {
    var isEnabled: Bool { false }
    var needsApproval: Bool { false }
    func setEnabled(_ enabled: Bool) throws {}
    func openSettings() {}
}
