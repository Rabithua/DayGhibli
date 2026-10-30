import AppKit

struct DesktopSnapshot: Codable {
    let displayID: UInt32
    let url: URL
    let scaling: Int?
    let clipping: Bool?
    let fill: [Double]?

    var options: [NSWorkspace.DesktopImageOptionKey: Any] {
        var result: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        if let scaling { result[.imageScaling] = NSNumber(value: scaling) }
        if let clipping { result[.allowClipping] = NSNumber(value: clipping) }
        if let fill, fill.count == 4 {
            result[.fillColor] = NSColor(srgbRed: fill[0], green: fill[1], blue: fill[2], alpha: fill[3])
        }
        return result
    }
}

struct DisplayWallpaper {
    let displayID: UInt32
    let file: URL
}

@MainActor
protocol DesktopApplying {
    var displayIDs: [UInt32] { get }
    func capture() -> [DesktopSnapshot]
    func apply(file: URL) throws
    func apply(assignments: [DisplayWallpaper]) throws
    func restore(_ snapshots: [DesktopSnapshot]) throws
}

extension DesktopApplying {
    // Compatibility defaults for existing single-display test doubles.
    var displayIDs: [UInt32] { [1] }

    func apply(assignments: [DisplayWallpaper]) throws {
        guard let first = assignments.first else { throw DesktopError.noScreen }
        try apply(file: first.file)
    }
}

@MainActor
struct DesktopController: DesktopApplying {
    var displayIDs: [UInt32] {
        NSScreen.screens.map { id(of: $0) }
    }

    private func id(of screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    func capture() -> [DesktopSnapshot] {
        capture(screens: NSScreen.screens)
    }

    private func capture(screens: [NSScreen]) -> [DesktopSnapshot] {
        screens.compactMap { screen in
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
            let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
            let color = (options[.fillColor] as? NSColor)?.usingColorSpace(.sRGB)
            return DesktopSnapshot(displayID: id(of: screen), url: url,
                scaling: (options[.imageScaling] as? NSNumber)?.intValue,
                clipping: (options[.allowClipping] as? NSNumber)?.boolValue,
                fill: color.map { [$0.redComponent, $0.greenComponent, $0.blueComponent, $0.alphaComponent] })
        }
    }

    func apply(file: URL) throws {
        try apply(assignments: displayIDs.map { DisplayWallpaper(displayID: $0, file: file) })
    }

    func apply(assignments: [DisplayWallpaper]) throws {
        let screens = NSScreen.screens
        guard !assignments.isEmpty, !screens.isEmpty else { throw DesktopError.noScreen }
        let connectedIDs = Set(screens.map { id(of: $0) })
        let assignedIDs = Set(assignments.map(\.displayID))
        guard assignedIDs.count == assignments.count,
              connectedIDs.count == screens.count,
              assignedIDs == connectedIDs else {
            throw DesktopError.displayChanged
        }

        let previous = capture(screens: screens)
        guard Set(previous.map(\.displayID)) == assignedIDs else {
            throw DesktopError.snapshotUnavailable
        }
        var changed: [DesktopSnapshot] = []
        do {
            for assignment in assignments {
                guard let screen = screens.first(where: { id(of: $0) == assignment.displayID }),
                      let snapshot = previous.first(where: { $0.displayID == assignment.displayID }) else {
                    throw DesktopError.displayChanged
                }
                try NSWorkspace.shared.setDesktopImageURL(assignment.file, for: screen, options: [
                    .imageScaling: NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue),
                    .allowClipping: true
                ])
                changed.append(snapshot)
            }
            guard Set(displayIDs) == assignedIDs else {
                throw DesktopError.displayChanged
            }
        } catch {
            // Attempt every changed display even when another display was disconnected.
            // A first-display failure has nothing to roll back.
            var rollbackFailed = false
            for snapshot in changed.reversed() {
                guard let screen = NSScreen.screens.first(where: { id(of: $0) == snapshot.displayID }) else {
                    rollbackFailed = true
                    continue
                }
                do {
                    try NSWorkspace.shared.setDesktopImageURL(snapshot.url, for: screen, options: snapshot.options)
                } catch {
                    rollbackFailed = true
                }
            }
            if rollbackFailed { throw DesktopError.rollbackFailed }
            throw error
        }
    }

    func restore(_ snapshots: [DesktopSnapshot]) throws {
        let screens = NSScreen.screens
        let connected = Set(screens.map { id(of: $0) })
        guard !snapshots.isEmpty, Set(snapshots.map(\.displayID)).isSubset(of: connected) else {
            throw DesktopError.noRestorableScreen
        }
        for screen in screens {
            guard let snapshot = snapshots.first(where: { $0.displayID == id(of: screen) }) else { continue }
            try NSWorkspace.shared.setDesktopImageURL(snapshot.url, for: screen, options: snapshot.options)
        }
    }
}

enum DesktopError: LocalizedError {
    case noScreen, displayChanged, snapshotUnavailable, noRestorableScreen, rollbackFailed

    var errorDescription: String? {
        switch self {
        case .noScreen: "未检测到可设置壁纸的显示器。"
        case .displayChanged: "显示器配置已变化，请重新点击换图。"
        case .snapshotUnavailable: "无法读取当前壁纸，暂未更换，请稍后重试。"
        case .noRestorableScreen: "原显示器未连接，暂时无法恢复。"
        case .rollbackFailed: "部分显示器切换失败，自动恢复也未完成，请在系统设置中检查壁纸。"
        }
    }
}
