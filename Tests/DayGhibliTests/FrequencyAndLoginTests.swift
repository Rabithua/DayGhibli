import Foundation
import XCTest
import WallpaperCore
@testable import DayGhibli

@MainActor
final class FrequencyAndLoginTests: XCTestCase {
    func testFrequencyDatesRespectIntervalsAndDailyWeeklyBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let friday = date(day: 30, hour: 23, minute: 45, calendar: calendar)
        XCTAssertEqual(ChangeFrequency.hourly.nextChange(after: friday, calendar: calendar)
            .timeIntervalSince(friday), 3_600)
        XCTAssertEqual(ChangeFrequency.sixHours.nextChange(after: friday, calendar: calendar)
            .timeIntervalSince(friday), 21_600)

        XCTAssertEqual(ChangeFrequency.daily.nextChange(
            after: date(day: 30, hour: 8, minute: 59, calendar: calendar), calendar: calendar),
            date(day: 30, hour: 9, calendar: calendar))
        XCTAssertEqual(ChangeFrequency.daily.nextChange(
            after: date(day: 30, hour: 9, calendar: calendar), calendar: calendar),
            date(day: 31, hour: 9, calendar: calendar))
        XCTAssertEqual(ChangeFrequency.daily.nextChange(
            after: date(day: 30, hour: 9, minute: 1, calendar: calendar), calendar: calendar),
            date(day: 31, hour: 9, calendar: calendar))

        let monday = date(month: 11, day: 2, hour: 9, calendar: calendar)
        let followingMonday = date(month: 11, day: 9, hour: 9, calendar: calendar)
        XCTAssertEqual(ChangeFrequency.weekly.nextChange(
            after: date(month: 11, day: 2, hour: 8, minute: 59, calendar: calendar), calendar: calendar),
            monday)
        XCTAssertEqual(ChangeFrequency.weekly.nextChange(after: monday, calendar: calendar), followingMonday)
        XCTAssertEqual(ChangeFrequency.weekly.nextChange(
            after: date(month: 11, day: 2, hour: 9, minute: 1, calendar: calendar), calendar: calendar),
            followingMonday)
        XCTAssertEqual(ChangeFrequency.weekly.nextChange(
            after: date(day: 31, hour: 22, calendar: calendar), calendar: calendar), monday)
        XCTAssertEqual(ChangeFrequency.weekly.nextChange(
            after: date(month: 11, day: 1, hour: 22, calendar: calendar), calendar: calendar), monday)
        XCTAssertEqual(Set(ChangeFrequency.allCases.map(\.title)), Set(["每小时", "每6小时", "每天", "每周"]))
    }

    func testFrequencyMigrationPersistenceAndReschedulingDoNotDownload() async throws {
        let fixture = try fixture()
        defer { fixture.cleanUp() }
        try Data(#"{"selectedFilmID":"all","seen":[],"previousDesktop":[]}"#.utf8)
            .write(to: fixture.directory.appendingPathComponent("state.json"))
        let clock = FrequencyClock(now: date(hour: 8))
        let downloader = FrequencyDownloader()
        let desktop = FrequencyDesktop()
        let login = FakeLoginItems()
        let model = WallpaperModel(catalog: fixture.catalog, directory: fixture.directory,
            downloader: downloader, desktop: desktop, loginItems: login, now: { clock.now })

        XCTAssertEqual(model.frequency, .daily)
        model.frequency = .hourly
        XCTAssertNil(model.nextAutomaticChange)
        model.autoEnabled = true
        XCTAssertEqual(model.nextAutomaticChange, clock.now.addingTimeInterval(3_600))
        model.frequency = .sixHours
        XCTAssertEqual(model.nextAutomaticChange, clock.now.addingTimeInterval(21_600))
        model.frequency = .daily
        XCTAssertEqual(model.nextAutomaticChange, date(hour: 9))
        model.frequency = .weekly
        XCTAssertEqual(model.nextAutomaticChange, date(month: 11, day: 2, hour: 9))

        let restored = WallpaperModel(catalog: fixture.catalog, directory: fixture.directory,
            downloader: downloader, desktop: desktop, loginItems: login, now: { clock.now })
        XCTAssertEqual(restored.frequency, .weekly)
        XCTAssertTrue(restored.autoEnabled)
        XCTAssertEqual(restored.nextAutomaticChange, date(month: 11, day: 2, hour: 9))
        restored.autoEnabled = false
        restored.frequency = .sixHours
        XCTAssertNil(restored.nextAutomaticChange)
        let disabled = WallpaperModel(catalog: fixture.catalog, directory: fixture.directory,
            downloader: downloader, desktop: desktop, loginItems: login, now: { clock.now })
        XCTAssertEqual(disabled.frequency, .sixHours)
        XCTAssertFalse(disabled.autoEnabled)
        XCTAssertNil(disabled.nextAutomaticChange)
        let requests = await downloader.requestCount()
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(desktop.applyCount, 0)
        XCTAssertTrue(login.setCalls.isEmpty)
    }

    func testChangingFrequencyClearsAutomaticRetryAndReschedulesWithoutAnotherDownload() async throws {
        let fixture = try fixture()
        defer { fixture.cleanUp() }
        let clock = FrequencyClock(now: date(hour: 8))
        let downloader = FrequencyDownloader()
        let desktop = FrequencyDesktop()
        let login = FakeLoginItems()
        let model = WallpaperModel(catalog: fixture.catalog, directory: fixture.directory,
            downloader: downloader, desktop: desktop, loginItems: login, now: { clock.now })
        model.autoEnabled = true
        clock.now = date(hour: 9)
        await model.checkAutomaticChange(at: clock.now)
        XCTAssertNotNil(model.automaticRetryAfter)

        model.frequency = .sixHours

        XCTAssertNil(model.automaticRetryAfter)
        XCTAssertEqual(model.nextAutomaticChange, clock.now.addingTimeInterval(21_600))
        let requests = await downloader.requestCount()
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(desktop.applyCount, 0)
    }

    func testLoginStatusComesFromServiceAndOnlyExplicitToggleRegisters() throws {
        let fixture = try fixture()
        defer { fixture.cleanUp() }
        let login = FakeLoginItems(isEnabled: true)
        let model = WallpaperModel(catalog: fixture.catalog, directory: fixture.directory,
            downloader: FrequencyDownloader(), desktop: FrequencyDesktop(), loginItems: login)

        XCTAssertTrue(model.loginAtLaunch)
        XCTAssertFalse(model.loginNeedsApproval)
        XCTAssertTrue(login.setCalls.isEmpty)
        model.startAutomaticScheduling()
        XCTAssertTrue(login.setCalls.isEmpty)

        model.setLoginAtLaunch(false)
        XCTAssertEqual(login.setCalls, [false])
        XCTAssertFalse(model.loginAtLaunch)
        XCTAssertFalse(login.isEnabled)
        model.setLoginAtLaunch(true)
        XCTAssertEqual(login.setCalls, [false, true])
        XCTAssertTrue(model.loginAtLaunch)
        XCTAssertTrue(login.isEnabled)

        login.isEnabled = false
        login.needsApproval = true
        model.refreshLoginItemStatus()
        XCTAssertFalse(model.loginAtLaunch)
        XCTAssertTrue(model.loginNeedsApproval)
        XCTAssertEqual(login.setCalls, [false, true])
        model.openLoginSettings()
        XCTAssertEqual(login.settingsOpenCount, 1)
    }

    func testLoginFailureRefreshesActualStatusAndReportsApprovalRequirement() throws {
        let fixture = try fixture()
        defer { fixture.cleanUp() }
        let login = FakeLoginItems()
        let model = WallpaperModel(catalog: fixture.catalog, directory: fixture.directory,
            downloader: FrequencyDownloader(), desktop: FrequencyDesktop(), loginItems: login)
        XCTAssertFalse(model.loginAtLaunch)
        login.isEnabled = true
        login.needsApproval = true
        login.shouldFail = true

        model.setLoginAtLaunch(false)

        XCTAssertEqual(login.setCalls, [false])
        XCTAssertTrue(model.loginAtLaunch)
        XCTAssertTrue(model.loginNeedsApproval)
        XCTAssertNotNil(model.errorMessage)
    }

    private func date(month: Int = 10, day: Int = 30, hour: Int, minute: Int = 0,
                      calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day,
                                           hour: hour, minute: minute))!
    }

    private func fixture() throws -> FrequencyFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DayGhibliFrequencyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = #"[{"id":"totoro001","filmID":"totoro","filmTitle":"龙猫","url":"https://www.ghibli.jp/gallery/totoro001.jpg"}]"#
        return FrequencyFixture(directory: directory,
            catalog: try JSONDecoder().decode([Wallpaper].self, from: Data(json.utf8)))
    }
}

private struct FrequencyFixture {
    let directory: URL
    let catalog: [Wallpaper]
    func cleanUp() { try? FileManager.default.removeItem(at: directory) }
}

@MainActor
private final class FrequencyClock {
    var now: Date
    init(now: Date) { self.now = now }
}

private enum FrequencyStubError: Error {
    case expectedFailure
}

private actor FrequencyDownloader: WallpaperDownloading {
    private var count = 0
    func download(_ image: Wallpaper) async throws -> URL {
        count += 1
        throw FrequencyStubError.expectedFailure
    }
    func requestCount() -> Int { count }
}

@MainActor
private final class FrequencyDesktop: DesktopApplying {
    private(set) var applyCount = 0
    func capture() -> [DesktopSnapshot] { [] }
    func apply(file: URL) throws { applyCount += 1 }
    func restore(_ snapshots: [DesktopSnapshot]) throws {}
}

@MainActor
private final class FakeLoginItems: LoginItemManaging {
    var isEnabled: Bool
    var needsApproval = false
    var shouldFail = false
    private(set) var setCalls: [Bool] = []
    private(set) var settingsOpenCount = 0

    init(isEnabled: Bool = false) { self.isEnabled = isEnabled }

    func setEnabled(_ enabled: Bool) throws {
        setCalls.append(enabled)
        if shouldFail { throw FrequencyStubError.expectedFailure }
        isEnabled = enabled
    }

    func openSettings() { settingsOpenCount += 1 }
}
