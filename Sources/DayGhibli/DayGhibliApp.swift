import AppKit
import SwiftUI

@main
struct DayGhibliApp: App {
    @State private var model: WallpaperModel
    @StateObject private var updater = AppUpdater()

    /// Totoro head silhouette shown in the menu bar. Cached once so repeated
    /// menu bar renders do not re-read the bundle resource. Falls back to a
    /// system symbol when the resource is missing (e.g. bare `swift run`).
    private static let menuBarIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        let height = CGFloat(17)
        image.size = NSSize(width: (height * image.size.width / image.size.height).rounded(), height: height)
        return image
    }()

    init() {
        let model = WallpaperModel()
        _model = State(initialValue: model)
        model.startAutomaticScheduling()
        Task { await model.cleanUpImages() }
    }

    var body: some Scene {
        MenuBarExtra {
            WallpaperMenu(model: model, updater: updater)
        } label: {
            if let icon = Self.menuBarIcon {
                Image(nsImage: icon)
                    .accessibilityLabel("每日吉卜力")
            } else {
                Image(systemName: "photo.on.rectangle.angled")
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
