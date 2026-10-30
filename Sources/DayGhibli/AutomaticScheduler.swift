import AppKit
import Foundation

@MainActor
final class AutomaticScheduler {
    private weak var model: WallpaperModel?
    private var timer: Timer?
    private var wakeObserver: (any NSObjectProtocol)?
    private var timeZoneObserver: (any NSObjectProtocol)?
    private var isStarted = false

    init(model: WallpaperModel) {
        self.model = model
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted, let model = self.model else { return }
                await model.checkAutomaticChange()
            }
        }

        timeZoneObserver = NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted, let model = self.model else { return }
                model.automaticTimeZoneChanged()
                self.schedule()
            }
        }

        schedule()
    }

    func schedule() {
        timer?.invalidate()
        timer = nil
        guard isStarted, let model, model.autoEnabled,
              let nextChange = model.nextAutomaticChange else { return }

        let earliest = Date().addingTimeInterval(model.isBusy ? 60 : 1)
        var fireDate = max(nextChange, earliest)
        if let retryAfter = model.automaticRetryAfter {
            fireDate = max(fireDate, retryAfter)
        }

        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted, let model = self.model else { return }
                await model.checkAutomaticChange()
            }
        }
        timer.tolerance = 1
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        isStarted = false
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let timeZoneObserver {
            NotificationCenter.default.removeObserver(timeZoneObserver)
        }
        wakeObserver = nil
        timeZoneObserver = nil
    }
}
