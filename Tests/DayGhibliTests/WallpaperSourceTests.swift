import Foundation
import XCTest
import WallpaperCore
@testable import DayGhibli

@MainActor
final class WallpaperSourceTests: XCTestCase {
    func testLegacySourcesMatchDisplayFilesRatherThanArrayOrderWithoutDownloading() async throws {
        let fixture = try SourceFixture()
        defer { fixture.cleanUp() }
        let first = fixture.catalog[0]
        let second = fixture.catalog[1]
        let firstFile = try fixture.cachedFile(for: first)
        let secondFile = try fixture.cachedFile(for: second)
        try fixture.writeState([
            "current": fixture.json(first), "currentFile": firstFile.absoluteString,
            "currentImages": [fixture.json(second), fixture.json(first)],
            "displayHistory": [
                ["displayID": 22, "current": secondFile.absoluteString],
                ["displayID": 11, "current": firstFile.absoluteString]
            ]
        ])
        let desktop = SourceDesktop(files: [11: firstFile, 22: secondFile])
        desktop.displayIDs = [22, 11]
        let downloader = SourceDownloader(directory: fixture.wallpapers)
        let model = fixture.model(desktop: desktop, downloader: downloader)

        assertSources(model, [11: first, 22: second])
        XCTAssertEqual(model.currentWallpaperSources.first { $0.id == 11 }?.displayName, "Mi Monitor")
        XCTAssertEqual(model.currentWallpaperSources.first { $0.id == 22 }?.displayName, "Wokyis")
        XCTAssertEqual(model.currentWallpaperSources.first { $0.id == 11 }?.image.workURL.absoluteString,
                       "https://www.ghibli.jp/works/totoro/")
        XCTAssertEqual(model.currentWallpaperSources.first { $0.id == 22 }?.image.workURL.absoluteString,
                       "https://www.ghibli.jp/works/chihiro/")
        XCTAssertEqual(model.currentWallpaperSources.first { $0.id == 11 }?.title, "Mi Monitor：龙猫")
        XCTAssertEqual(model.currentWallpaperSources.first { $0.id == 22 }?.title, "Wokyis：千与千寻")
        model.refreshWallpaperSources()

        assertSources(model, [11: first, 22: second])
        let requests = await downloader.downloads()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(desktop.applyCount, 0)
    }

    func testIndependentChangesUpdateEachSourceAndRestoreItsOwnPreviousImage() async throws {
        let fixture = try SourceFixture()
        defer { fixture.cleanUp() }
        let desktop = SourceDesktop(files: fixture.externalFiles)
        let downloader = SourceDownloader(directory: fixture.wallpapers)
        let model = fixture.model(desktop: desktop, downloader: downloader)
        model.differentWallpapers = true

        await model.changeNow()

        let first = expectedSources(desktop: desktop, downloads: await downloader.downloads())
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(Set(first.values.map(\.id)).count, 2)
        assertSources(model, first)
        desktop.displayIDs.reverse()

        await model.changeNow()

        let second = expectedSources(desktop: desktop, downloads: await downloader.downloads())
        XCTAssertTrue(Set(first.values.map(\.id)).isDisjoint(with: Set(second.values.map(\.id))))
        assertSources(model, second)

        await model.restorePreviousWallpaper()

        assertSources(model, first)
        model.refreshWallpaperSources()
        assertSources(model, first)
        XCTAssertNil(model.errorMessage)
    }

    func testSharedImageUsesTheSameWorkPageForBothDisplays() async throws {
        let fixture = try SourceFixture()
        defer { fixture.cleanUp() }
        let desktop = SourceDesktop(files: fixture.externalFiles)
        let downloader = SourceDownloader(directory: fixture.wallpapers)
        let model = fixture.model(desktop: desktop, downloader: downloader)

        await model.changeNow()

        let downloads = await downloader.downloads()
        XCTAssertEqual(downloads.count, 1)
        let image = try XCTUnwrap(downloads.first?.image)
        assertSources(model, [11: image, 22: image])
        XCTAssertEqual(Set(model.currentWallpaperSources.map { $0.image.url }), [image.url])
        XCTAssertEqual(Set(model.currentWallpaperSources.map { $0.image.workURL }), [image.workURL])
        XCTAssertNil(model.errorMessage)
    }

    func testPersistedDisplayMetadataSurvivesRestartWithoutFilenameInference() async throws {
        let fixture = try SourceFixture()
        defer { fixture.cleanUp() }
        let desktop = SourceDesktop(files: fixture.externalFiles)
        let downloader = SourceDownloader(directory: fixture.wallpapers)
        let model = fixture.model(desktop: desktop, downloader: downloader)
        model.differentWallpapers = true
        await model.changeNow()
        let expected = expectedSources(desktop: desktop, downloads: await downloader.downloads())
        XCTAssertTrue(desktop.files.values.allSatisfy { $0.lastPathComponent.hasPrefix("download-") })
        desktop.displayIDs.reverse()

        let restarted = fixture.model(desktop: desktop, downloader: downloader)

        assertSources(restarted, expected)
        restarted.refreshWallpaperSources()
        assertSources(restarted, expected)
        let downloads = await downloader.downloads()
        XCTAssertEqual(downloads.count, 2)
    }

    func testRefreshingExternalChangesAndDisconnectedDisplaysRemovesStaleSources() async throws {
        let fixture = try SourceFixture()
        defer { fixture.cleanUp() }
        let first = fixture.catalog[0]
        let second = fixture.catalog[1]
        let firstFile = try fixture.cachedFile(for: first)
        let secondFile = try fixture.cachedFile(for: second)
        try fixture.writeState([
            "current": fixture.json(first), "currentFile": firstFile.absoluteString,
            "currentImages": [fixture.json(first), fixture.json(second)],
            "displayHistory": [
                ["displayID": 11, "current": firstFile.absoluteString],
                ["displayID": 22, "current": secondFile.absoluteString]
            ]
        ])
        let desktop = SourceDesktop(files: [11: firstFile, 22: secondFile])
        let downloader = SourceDownloader(directory: fixture.wallpapers)
        let model = fixture.model(desktop: desktop, downloader: downloader)
        assertSources(model, [11: first, 22: second])

        desktop.files[11] = fixture.externalFiles[11]
        model.refreshWallpaperSources()

        assertSources(model, [22: second])
        XCTAssertEqual(model.currentWallpaperSources.first?.title, "Wokyis：千与千寻")
        desktop.displayIDs = [22]
        model.refreshWallpaperSources()
        assertSources(model, [22: second])
        XCTAssertEqual(model.currentWallpaperSources.first?.title, "千与千寻")
        desktop.displayIDs = [11]
        model.refreshWallpaperSources()

        XCTAssertTrue(model.currentWallpaperSources.isEmpty)
        let downloads = await downloader.downloads()
        XCTAssertTrue(downloads.isEmpty)
        XCTAssertEqual(desktop.applyCount, 0)
    }

    func testDownloadAndApplyFailuresKeepExistingSourceAssociation() async throws {
        let fixture = try SourceFixture()
        defer { fixture.cleanUp() }
        let desktop = SourceDesktop(files: fixture.externalFiles)
        let downloader = SourceDownloader(directory: fixture.wallpapers)
        let model = fixture.model(desktop: desktop, downloader: downloader)
        model.differentWallpapers = true
        await model.changeNow()
        let expected = expectedSources(desktop: desktop, downloads: await downloader.downloads())
        await downloader.setFailing(true)

        await model.changeNow()

        assertSources(model, expected)
        XCTAssertNotNil(model.errorMessage)
        await downloader.setFailing(false)
        desktop.shouldFail = true

        await model.changeNow()

        assertSources(model, expected)
        model.refreshWallpaperSources()
        assertSources(model, expected)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(desktop.applyCount, 1)
    }

    func testRestoringAnExternalWallpaperDoesNotInheritPreviouslyKnownImageMetadata() async throws {
        let fixture = try SourceFixture()
        defer { fixture.cleanUp() }
        let desktop = SourceDesktop(files: fixture.externalFiles)
        let downloader = SourceDownloader(directory: fixture.wallpapers)
        let model = fixture.model(desktop: desktop, downloader: downloader)
        model.differentWallpapers = true
        await model.changeNow()
        XCTAssertEqual(model.currentWallpaperSources.count, 2)

        // An external app changes both desktops. The next download must record
        // these unknown files as the actual previous wallpapers without carrying
        // over the metadata from the last images DayGhibli assigned.
        desktop.files = fixture.externalFiles
        await model.changeNow()
        XCTAssertEqual(model.currentWallpaperSources.count, 2)

        await model.restorePreviousWallpaper()

        XCTAssertEqual(desktop.files, fixture.externalFiles)
        XCTAssertTrue(model.currentWallpaperSources.isEmpty)
        model.refreshWallpaperSources()
        XCTAssertTrue(model.currentWallpaperSources.isEmpty)
        let restarted = fixture.model(desktop: desktop, downloader: downloader)
        XCTAssertTrue(restarted.currentWallpaperSources.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    func testUnknownDesktopWithoutSavedStateHasNoInventedSource() async throws {
        let fixture = try SourceFixture()
        defer { fixture.cleanUp() }
        let desktop = SourceDesktop(files: fixture.externalFiles)
        let downloader = SourceDownloader(directory: fixture.wallpapers)
        let model = fixture.model(desktop: desktop, downloader: downloader)

        XCTAssertTrue(model.currentWallpaperSources.isEmpty)
        model.refreshWallpaperSources()

        XCTAssertTrue(model.currentWallpaperSources.isEmpty)
        let downloads = await downloader.downloads()
        XCTAssertTrue(downloads.isEmpty)
    }

    private func assertSources(_ model: WallpaperModel, _ expected: [UInt32: Wallpaper],
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(model.currentWallpaperSources.count, expected.count, file: file, line: line)
        let actual = Dictionary(uniqueKeysWithValues: model.currentWallpaperSources.map { ($0.id, $0.image) })
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    private func expectedSources(desktop: SourceDesktop,
                                 downloads: [SourceDownload]) -> [UInt32: Wallpaper] {
        Dictionary(uniqueKeysWithValues: desktop.displayIDs.compactMap { id in
            guard let image = downloads.last(where: { $0.file == desktop.files[id] })?.image else { return nil }
            return (id, image)
        })
    }
}

@MainActor
private struct SourceFixture {
    let directory: URL
    let wallpapers: URL
    let catalog: [Wallpaper]

    var externalFiles: [UInt32: URL] {
        [11: directory.appendingPathComponent("external-11.jpg"),
         22: directory.appendingPathComponent("external-22.jpg")]
    }

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayGhibliSourceTests-\(UUID().uuidString)")
        wallpapers = directory.appendingPathComponent("Wallpapers")
        try FileManager.default.createDirectory(at: wallpapers, withIntermediateDirectories: true)
        let json = #"[{"id":"totoro001","filmID":"totoro","filmTitle":"龙猫","url":"https://www.ghibli.jp/gallery/totoro001.jpg"},{"id":"chihiro001","filmID":"chihiro","filmTitle":"千与千寻","url":"https://www.ghibli.jp/gallery/chihiro001.jpg"},{"id":"aya001","filmID":"aya","filmTitle":"安雅与魔女","url":"https://www.ghibli.jp/gallery/aya001.jpg"},{"id":"ged001","filmID":"ged","filmTitle":"地海战记","url":"https://www.ghibli.jp/gallery/ged001.jpg"}]"#
        catalog = try JSONDecoder().decode([Wallpaper].self, from: Data(json.utf8))
    }

    func model(desktop: SourceDesktop, downloader: SourceDownloader) -> WallpaperModel {
        WallpaperModel(catalog: catalog, directory: directory, downloader: downloader,
                       desktop: desktop, loginItems: SourceLoginItems())
    }

    func cachedFile(for image: Wallpaper) throws -> URL {
        let url = wallpapers.appendingPathComponent("\(image.id)-\(UUID().uuidString).jpg")
        try Data([1]).write(to: url)
        return url
    }

    func json(_ image: Wallpaper) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(image))
    }

    func writeState(_ dictionary: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: dictionary)
            .write(to: directory.appendingPathComponent("state.json"))
    }

    func cleanUp() { try? FileManager.default.removeItem(at: directory) }
}

private struct SourceDownload: Sendable {
    let file: URL
    let image: Wallpaper
}

private enum SourceStubError: Error { case failure }

private actor SourceDownloader: WallpaperDownloading {
    private let directory: URL
    private var completed: [SourceDownload] = []
    private var failing = false

    init(directory: URL) { self.directory = directory }

    func download(_ image: Wallpaper) async throws -> URL {
        if failing { throw SourceStubError.failure }
        // Deliberately opaque names prove the new metadata uses the assigned file,
        // rather than depending on the download order or parsing image IDs.
        let file = directory.appendingPathComponent("download-\(UUID().uuidString).jpg")
        try Data([1]).write(to: file)
        completed.append(SourceDownload(file: file, image: image))
        return file
    }

    func downloads() -> [SourceDownload] { completed }
    func setFailing(_ value: Bool) { failing = value }
}

@MainActor
private final class SourceDesktop: DesktopApplying {
    var displayIDs: [UInt32] = [11, 22]
    var files: [UInt32: URL]
    var shouldFail = false
    private(set) var applyCount = 0

    init(files: [UInt32: URL]) { self.files = files }

    func displayName(for displayID: UInt32) -> String {
        displayID == 11 ? "Mi Monitor" : "Wokyis"
    }

    func capture() -> [DesktopSnapshot] {
        displayIDs.reversed().compactMap { id in
            files[id].map {
                DesktopSnapshot(displayID: id, url: $0, scaling: nil, clipping: nil, fill: nil)
            }
        }
    }

    func apply(file: URL) throws {
        try apply(assignments: displayIDs.map { DisplayWallpaper(displayID: $0, file: file) })
    }

    func apply(assignments: [DisplayWallpaper]) throws {
        if shouldFail { throw SourceStubError.failure }
        applyCount += 1
        for assignment in assignments { files[assignment.displayID] = assignment.file }
    }

    func restore(_ snapshots: [DesktopSnapshot]) throws {
        if shouldFail { throw SourceStubError.failure }
        for snapshot in snapshots { files[snapshot.displayID] = snapshot.url }
    }
}

@MainActor
private struct SourceLoginItems: LoginItemManaging {
    var isEnabled: Bool { false }
    var needsApproval: Bool { false }
    func setEnabled(_ enabled: Bool) throws {}
    func openSettings() {}
}
