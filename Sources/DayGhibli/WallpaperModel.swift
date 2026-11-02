import AppKit
import Observation
import WallpaperCore

struct WallpaperSource: Identifiable, Equatable {
    let id: UInt32
    let displayName: String
    let image: Wallpaper
    let showsDisplayName: Bool

    var title: String {
        showsDisplayName ? "\(displayName)：\(image.filmTitle)" : image.filmTitle
    }
}

private struct DisplayHistory: Codable {
    let displayID: UInt32
    var current: URL
    var previous: URL?
    var currentImage: Wallpaper?
    var previousImage: Wallpaper?
}

private struct SavedState: Codable {
    var selectedFilmID = "all"
    var current: Wallpaper?
    var currentFile: URL?
    var lastChanged: Date?
    var seen: [String] = []
    var previousDesktop: [DesktopSnapshot] = []
    var previousImage: Wallpaper?
    var previousFile: URL?
    var currentImages: [Wallpaper] = []
    var previousImages: [Wallpaper] = []
    var differentWallpapers = false
    var autoEnabled = false
    var frequency = ChangeFrequency.daily
    var nextAutomaticChange: Date?
    var displayHistory: [DisplayHistory] = []

    init() {}

    enum CodingKeys: String, CodingKey {
        case selectedFilmID, current, currentFile, lastChanged, seen
        case previousDesktop, previousImage, previousFile, currentImages, previousImages
        case differentWallpapers, autoEnabled, frequency, nextAutomaticChange, displayHistory
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        selectedFilmID = try values.decodeIfPresent(String.self, forKey: .selectedFilmID) ?? "all"
        current = try values.decodeIfPresent(Wallpaper.self, forKey: .current)
        currentFile = try values.decodeIfPresent(URL.self, forKey: .currentFile)
        lastChanged = try values.decodeIfPresent(Date.self, forKey: .lastChanged)
        seen = try values.decodeIfPresent([String].self, forKey: .seen) ?? []
        previousDesktop = try values.decodeIfPresent([DesktopSnapshot].self, forKey: .previousDesktop) ?? []
        previousImage = try values.decodeIfPresent(Wallpaper.self, forKey: .previousImage)
        previousFile = try values.decodeIfPresent(URL.self, forKey: .previousFile)
        currentImages = try values.decodeIfPresent([Wallpaper].self, forKey: .currentImages) ?? [current].compactMap { $0 }
        previousImages = try values.decodeIfPresent([Wallpaper].self, forKey: .previousImages) ?? [previousImage].compactMap { $0 }
        differentWallpapers = try values.decodeIfPresent(Bool.self, forKey: .differentWallpapers) ?? false
        autoEnabled = try values.decodeIfPresent(Bool.self, forKey: .autoEnabled) ?? false
        frequency = (try? values.decode(ChangeFrequency.self, forKey: .frequency)) ?? .daily
        nextAutomaticChange = try values.decodeIfPresent(Date.self, forKey: .nextAutomaticChange)
        displayHistory = try values.decodeIfPresent([DisplayHistory].self, forKey: .displayHistory) ?? []
    }
}

@MainActor @Observable
final class WallpaperModel {
    var selectedFilmID = "all" {
        didSet { if !isLoadingState && selectedFilmID != oldValue { save() } }
    }
    var differentWallpapers = false {
        didSet { if !isLoadingState && differentWallpapers != oldValue { save() } }
    }
    var autoEnabled = false {
        didSet {
            guard !isLoadingState, autoEnabled != oldValue else { return }
            nextAutomaticChange = autoEnabled ? frequency.nextChange(after: now()) : nil
            automaticRetryAfter = nil
            save()
            automaticScheduler?.schedule()
        }
    }

    var frequency = ChangeFrequency.daily {
        didSet {
            guard !isLoadingState, frequency != oldValue else { return }
            nextAutomaticChange = autoEnabled ? frequency.nextChange(after: now()) : nil
            automaticRetryAfter = nil
            save()
            automaticScheduler?.schedule()
        }
    }

    private(set) var current: Wallpaper?
    private(set) var currentWallpaperSources: [WallpaperSource] = []
    private(set) var loginAtLaunch = false
    private(set) var loginNeedsApproval = false
    private(set) var lastChanged: Date?
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var canRevert = false
    private(set) var nextAutomaticChange: Date?
    private(set) var automaticRetryAfter: Date?
    let films: [FilmOption]

    private let catalog: [Wallpaper]
    private let downloader: any WallpaperDownloading
    private let desktop: any DesktopApplying
    private let loginItems: any LoginItemManaging
    private let stateURL: URL
    private let imageDirectory: URL
    private let now: @MainActor () -> Date
    private var state: SavedState
    @ObservationIgnored private var automaticScheduler: AutomaticScheduler?
    @ObservationIgnored private var isLoadingState = true

    var imageCount: Int {
        catalog.filter { selectedFilmID == "all" || $0.filmID == selectedFilmID }.count
    }

    init(catalog suppliedCatalog: [Wallpaper]? = nil, directory: URL? = nil,
         downloader: (any WallpaperDownloading)? = nil,
         desktop: (any DesktopApplying)? = nil,
         loginItems: (any LoginItemManaging)? = nil,
         now: @escaping @MainActor () -> Date = Date.init) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory,
            in: .userDomainMask)[0].appendingPathComponent("DayGhibli", isDirectory: true)
        self.stateURL = base.appendingPathComponent("state.json")
        self.imageDirectory = base.appendingPathComponent("Wallpapers")
        self.downloader = downloader ?? ImageStore(directory: imageDirectory)
        self.desktop = desktop ?? DesktopController()
        self.loginItems = loginItems ?? LoginItemController()
        self.now = now
        let loaded = suppliedCatalog ?? Self.loadCatalog()
        self.catalog = loaded
        var seenFilms: Set<String> = []
        self.films = [FilmOption(id: "all", title: "全部作品")] + loaded.compactMap {
            seenFilms.insert($0.filmID).inserted ? FilmOption(id: $0.filmID, title: $0.filmTitle) : nil
        }
        self.state = (try? JSONDecoder().decode(SavedState.self,
            from: Data(contentsOf: stateURL))) ?? SavedState()
        self.selectedFilmID = films.contains(where: { $0.id == state.selectedFilmID }) ? state.selectedFilmID : "all"
        self.current = state.current
        self.lastChanged = state.lastChanged
        self.canRevert = !state.previousDesktop.isEmpty
        self.differentWallpapers = state.differentWallpapers
        self.frequency = state.frequency
        self.autoEnabled = state.autoEnabled
        self.nextAutomaticChange = state.autoEnabled
            ? (state.nextAutomaticChange ?? frequency.nextChange(after: now())) : nil
        if loaded.isEmpty { self.errorMessage = "图片目录无法加载。" }
        self.isLoadingState = false
        refreshLoginItemStatus()
        refreshWallpaperSources()
        // Only local state is read here. Scheduling begins explicitly from the App.
    }

    func startAutomaticScheduling() {
        guard automaticScheduler == nil else { return }
        let scheduler = AutomaticScheduler(model: self)
        automaticScheduler = scheduler
        scheduler.start()
    }

    func automaticTimeZoneChanged() {
        if frequency.isCalendarBased, autoEnabled, let nextAutomaticChange, nextAutomaticChange > now() {
            self.nextAutomaticChange = frequency.nextChange(after: now())
            save()
        }
        automaticScheduler?.schedule()
    }

    func refreshLoginItemStatus() {
        loginAtLaunch = loginItems.isEnabled
        loginNeedsApproval = loginItems.needsApproval
    }

    func refreshWallpaperSources() {
        guard !isBusy else { return }
        updateWallpaperSources(files: desktop.capture().reduce(into: [:]) {
            $0[$1.displayID] = $1.url
        })
    }

    private func updateWallpaperSources(files: [UInt32: URL]) {
        let displayIDs = desktop.displayIDs
        let names = displayIDs.map { desktop.displayName(for: $0) }
        currentWallpaperSources = displayIDs.enumerated().compactMap { index, displayID in
            guard let file = files[displayID], let image = wallpaper(for: file) else { return nil }
            let name = names[index]
            let displayName = names.filter { $0 == name }.count > 1 ? "\(name) (\(index + 1))" : name
            return WallpaperSource(id: displayID, displayName: displayName, image: image,
                                   showsDisplayName: displayIDs.count > 1)
        }
    }

    private func wallpaper(for file: URL) -> Wallpaper? {
        guard file.isFileURL else { return nil }
        let normalized = file.standardizedFileURL.resolvingSymlinksInPath()
        func matches(_ url: URL?) -> Bool {
            url?.standardizedFileURL.resolvingSymlinksInPath() == normalized
        }
        var image: Wallpaper?
        for entry in state.displayHistory {
            if matches(entry.current), let known = entry.currentImage { image = known; break }
            if matches(entry.previous), let known = entry.previousImage { image = known; break }
        }
        if image == nil, matches(state.currentFile) { image = state.current }
        if image == nil, matches(state.previousFile) { image = state.previousImage }
        if image == nil,
           normalized.deletingLastPathComponent() == imageDirectory.standardizedFileURL.resolvingSymlinksInPath() {
            // Older states stored per-display files without image metadata. Recover only
            // our own cache naming format, never guess from display or array order.
            let stem = normalized.deletingPathExtension().lastPathComponent
            image = (state.currentImages + state.previousImages + catalog).first { candidate in
                stem == candidate.id || (stem.hasPrefix(candidate.id + "-") &&
                    UUID(uuidString: String(stem.dropFirst(candidate.id.count + 1))) != nil)
            }
        }
        guard let image, image.url.scheme == "https", image.url.host == "www.ghibli.jp",
              image.url.path.hasPrefix("/gallery/") else { return nil }
        return image
    }

    func setLoginAtLaunch(_ enabled: Bool) {
        errorMessage = nil
        defer { refreshLoginItemStatus() }
        do {
            try loginItems.setEnabled(enabled)
        } catch {
            errorMessage = "登录启动设置失败：\(error.localizedDescription)"
        }
    }

    func openLoginSettings() {
        loginItems.openSettings()
    }

    func changeNow() async {
        await change(isAutomatic: false, at: now())
    }

    func checkAutomaticChange(at date: Date? = nil) async {
        let time = date ?? now()
        guard autoEnabled, let due = nextAutomaticChange, time >= due,
              automaticRetryAfter.map({ time >= $0 }) ?? true else {
            automaticScheduler?.schedule()
            return
        }
        await change(isAutomatic: true, at: time)
    }

    private func change(isAutomatic: Bool, at requestedTime: Date) async {
        guard !isBusy else {
            automaticScheduler?.schedule()
            return
        }
        isBusy = true
        errorMessage = nil
        defer {
            isBusy = false
            automaticScheduler?.schedule()
        }
        do {
            let displayIDs = desktop.displayIDs
            guard !displayIDs.isEmpty else { throw DesktopError.noScreen }
            let independent = differentWallpapers
            let count = independent ? displayIDs.count : 1
            let images = try chooseImages(count: count)
            var files: [URL] = []
            for image in images {
                files.append(try await downloader.download(image))
            }
            if isAutomatic && !autoEnabled { return }
            let assignments = displayIDs.enumerated().map { index, displayID in
                DisplayWallpaper(displayID: displayID, file: files[independent ? index : 0])
            }
            let before = desktop.capture()
            try desktop.apply(assignments: assignments)

            recordHistory(assignments: assignments, before: before,
                          images: Dictionary(uniqueKeysWithValues: zip(files, images)))

            state.previousDesktop = before
            state.previousImage = current
            state.previousFile = state.currentFile
            state.previousImages = state.currentImages
            state.current = images[0]
            state.currentFile = files[0]
            state.currentImages = images
            state.lastChanged = max(requestedTime, now())
            state.seen.append(contentsOf: images.map(\.id))
            state.seen = Array(state.seen.suffix(catalog.count))
            current = images[0]
            lastChanged = state.lastChanged
            canRevert = !before.isEmpty
            updateWallpaperSources(files: Dictionary(uniqueKeysWithValues: assignments.map { ($0.displayID, $0.file) }))
            automaticRetryAfter = nil
            if autoEnabled {
                nextAutomaticChange = frequency.nextChange(after: state.lastChanged!)
            }
            await persistAndPruneImages()
        } catch {
            errorMessage = "更换失败：\(error.localizedDescription)"
            if isAutomatic {
                automaticRetryAfter = max(requestedTime, now()).addingTimeInterval(15 * 60)
            }
        }
    }

    private func chooseImages(count: Int) throws -> [Wallpaper] {
        let matching = catalog.filter { selectedFilmID == "all" || $0.filmID == selectedFilmID }
        guard matching.count >= count else {
            throw SelectionError.insufficientImages
        }
        let seen = Set(state.seen)
        let currentIDs = Set(state.currentImages.map(\.id)).union([current?.id].compactMap { $0 })
        var chosen: [Wallpaper] = []
        for _ in 0..<count {
            let chosenIDs = Set(chosen.map(\.id))
            let available = matching.filter { !chosenIDs.contains($0.id) }
            let unseen = available.filter { !seen.contains($0.id) && !currentIDs.contains($0.id) }
            let different = available.filter { !currentIDs.contains($0.id) }
            let pool = !unseen.isEmpty ? unseen : (!different.isEmpty ? different : available)
            guard let image = pool.randomElement() else { throw SelectionError.insufficientImages }
            chosen.append(image)
        }
        return chosen
    }

    func restorePreviousWallpaper() async {
        guard !isBusy, canRevert else { return }
        isBusy = true
        defer {
            isBusy = false
            automaticScheduler?.schedule()
        }
        errorMessage = nil
        do {
            let before = desktop.capture()
            try desktop.restore(state.previousDesktop)
            recordHistory(assignments: state.previousDesktop.map {
                DisplayWallpaper(displayID: $0.displayID, file: $0.url)
            }, before: before)
            state.current = state.previousImage
            state.currentFile = state.previousFile
            state.currentImages = state.previousImages
            state.previousDesktop = []
            state.previousImage = nil
            state.previousFile = nil
            state.previousImages = []
            state.lastChanged = now()
            current = state.current
            lastChanged = state.lastChanged
            canRevert = false
            updateWallpaperSources(files: Dictionary(uniqueKeysWithValues: state.displayHistory.map { ($0.displayID, $0.current) }))
            await persistAndPruneImages()
        } catch {
            errorMessage = "恢复失败：\(error.localizedDescription)"
        }
    }

    func cleanUpImages() async {
        guard !isBusy else { return }
        isBusy = true
        defer {
            isBusy = false
            automaticScheduler?.schedule()
        }
        let snapshots = desktop.capture()
        let connectedIDs = Set(desktop.displayIDs)
        guard !connectedIDs.isEmpty, Set(snapshots.map(\.displayID)) == connectedIDs else { return }
        for snapshot in snapshots {
            let image = wallpaper(for: snapshot.url)
            if let index = state.displayHistory.firstIndex(where: { $0.displayID == snapshot.displayID }) {
                if state.displayHistory[index].current.standardizedFileURL != snapshot.url.standardizedFileURL {
                    state.displayHistory[index].previousImage = wallpaper(for: state.displayHistory[index].current)
                    state.displayHistory[index].previous = state.displayHistory[index].current
                    state.displayHistory[index].current = snapshot.url
                }
                state.displayHistory[index].currentImage = image
            } else {
                let previous = state.previousDesktop.first { $0.displayID == snapshot.displayID }?.url
                state.displayHistory.append(DisplayHistory(displayID: snapshot.displayID,
                    current: snapshot.url,
                    previous: previous?.standardizedFileURL == snapshot.url.standardizedFileURL ? nil : previous,
                    currentImage: image, previousImage: previous.flatMap { wallpaper(for: $0) }))
            }
        }
        updateWallpaperSources(files: snapshots.reduce(into: [:]) { $0[$1.displayID] = $1.url })
        await persistAndPruneImages()
    }

    private func recordHistory(assignments: [DisplayWallpaper], before: [DesktopSnapshot],
                               images: [URL: Wallpaper] = [:]) {
        for assignment in assignments {
            let previous = before.first { $0.displayID == assignment.displayID }?.url
            let currentImage = images[assignment.file] ?? wallpaper(for: assignment.file)
            let previousImage = previous.flatMap { wallpaper(for: $0) }
            if let index = state.displayHistory.firstIndex(where: { $0.displayID == assignment.displayID }) {
                let old = state.displayHistory[index]
                state.displayHistory[index] = DisplayHistory(displayID: assignment.displayID,
                    current: assignment.file,
                    previous: previous?.standardizedFileURL == assignment.file.standardizedFileURL
                        ? old.previous : (previous ?? old.current),
                    currentImage: currentImage,
                    previousImage: previous?.standardizedFileURL == assignment.file.standardizedFileURL
                        ? old.previousImage : (previous == nil ? wallpaper(for: old.current) : previousImage))
            } else {
                state.displayHistory.append(DisplayHistory(displayID: assignment.displayID,
                    current: assignment.file,
                    previous: previous?.standardizedFileURL == assignment.file.standardizedFileURL ? nil : previous,
                    currentImage: currentImage,
                    previousImage: previous?.standardizedFileURL == assignment.file.standardizedFileURL ? nil : previousImage))
            }
        }
    }

    private func persistAndPruneImages() async {
        guard save() else { return }
        let keep = Set(state.displayHistory.flatMap { [$0.current] + [$0.previous].compactMap { $0 } })
        do {
            try await downloader.prune(keeping: keep)
        } catch {
            errorMessage = "图片清理失败：\(error.localizedDescription)"
        }
    }

    @discardableResult
    private func save() -> Bool {
        state.selectedFilmID = selectedFilmID
        state.differentWallpapers = differentWallpapers
        state.autoEnabled = autoEnabled
        state.frequency = frequency
        state.nextAutomaticChange = nextAutomaticChange
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
            return true
        } catch {
            errorMessage = "设置保存失败：\(error.localizedDescription)"
            return false
        }
    }

    private static func loadCatalog() -> [Wallpaper] {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let bytes = try? Data(contentsOf: url),
              let images = try? JSONDecoder().decode([Wallpaper].self, from: bytes) else { return [] }
        return images
    }
}

private enum SelectionError: LocalizedError {
    case insufficientImages
    var errorDescription: String? { "当前作品的图片不足，请选择其他作品。" }
}
