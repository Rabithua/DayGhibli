import AppKit
import SwiftUI

@main
struct DayGhibliApp: App {
    @State private var model: WallpaperModel
    @StateObject private var updater = AppUpdater()

    init() {
        let model = WallpaperModel()
        _model = State(initialValue: model)
        model.startAutomaticScheduling()
        Task { await model.cleanUpImages() }
    }

    var body: some Scene {
        MenuBarExtra("每日吉卜力", systemImage: "photo.on.rectangle.angled") {
            WallpaperMenu(model: model, updater: updater)
        }
        .menuBarExtraStyle(.menu)
    }
}
