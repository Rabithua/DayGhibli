import Foundation

public struct Wallpaper: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let filmID: String
    public let filmTitle: String
    public let url: URL
}

public struct FilmOption: Identifiable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public enum DailySchedule {
    public static func nextChange(after now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now,
            matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)!
        if today > now { return today }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow,
            matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)!
    }
}

public enum ChangeFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case hourly, sixHours, daily, weekly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .hourly: "每小时"
        case .sixHours: "每6小时"
        case .daily: "每天"
        case .weekly: "每周"
        }
    }

    public var isCalendarBased: Bool { self == .daily || self == .weekly }

    public func nextChange(after now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .hourly: now.addingTimeInterval(60 * 60)
        case .sixHours: now.addingTimeInterval(6 * 60 * 60)
        case .daily: DailySchedule.nextChange(after: now, calendar: calendar)
        case .weekly:
            calendar.nextDate(after: now,
                matching: DateComponents(hour: 9, minute: 0, second: 0, weekday: 2),
                matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)!
        }
    }
}

public enum Rotation {
    public static func pool(in images: [Wallpaper], filmID: String,
                            seen: Set<String>, currentID: String?) -> [Wallpaper] {
        let matching = images.filter { filmID == "all" || $0.filmID == filmID }
        let unseen = matching.filter { !seen.contains($0.id) && $0.id != currentID }
        if !unseen.isEmpty { return unseen }
        let different = matching.filter { $0.id != currentID }
        return different.isEmpty ? matching : different
    }
}
