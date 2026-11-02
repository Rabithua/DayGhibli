import AppKit
import SwiftUI
import WallpaperCore

@MainActor
struct WallpaperMenu: View {
    @Bindable var model: WallpaperModel

    var body: some View {
        Group {
            Section("操作") {
                Button(model.isBusy ? "正在更换…" : "换一张") {
                    Task { await model.changeNow() }
                }
                .disabled(model.isBusy || model.imageCount == 0)

                Picker("影片", selection: $model.selectedFilmID) {
                    ForEach(model.films) { film in
                        Text(film.title).tag(film.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(model.isBusy)

                Button("恢复上次壁纸") {
                    Task { await model.restorePreviousWallpaper() }
                }
                .disabled(!model.canRevert || model.isBusy)

                if model.errorMessage != nil {
                    Button("查看错误…", action: showError)
                }
            }

            if !model.currentWallpaperSources.isEmpty {
                Section("壁纸信息") {
                    ForEach(model.currentWallpaperSources) { source in
                        Link(source.title, destination: source.image.url)
                    }
                }
            }

            Section("设置") {
                Toggle("各显示器独立随机", isOn: $model.differentWallpapers)
                    .disabled(model.isBusy)
                Toggle("自动切换", isOn: $model.autoEnabled)

                Picker("切换频率", selection: $model.frequency) {
                    ForEach(ChangeFrequency.allCases) { frequency in
                        Text(frequency.title).tag(frequency)
                    }
                }
                .pickerStyle(.menu)
                .disabled(model.isBusy)

                Toggle("登录时启动", isOn: Binding(
                    get: { model.loginAtLaunch },
                    set: { model.setLoginAtLaunch($0) }
                ))
                if model.loginNeedsApproval {
                    Button("在系统设置中允许…", action: model.openLoginSettings)
                }
            }

            Divider()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .onAppear {
            model.refreshLoginItemStatus()
            model.refreshWallpaperSources()
        }
    }

    private func showError() {
        guard let message = model.errorMessage else { return }
        let alert = NSAlert()
        alert.messageText = "操作失败"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        NSApplication.shared.activate()
        alert.runModal()
    }
}
