import Foundation
import EventKit

enum EventMapper {
    private static let formatters: [ISO8601DateFormatter] = [
        {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }(),
        {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()
    ]

    private static let outputFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseISO(_ s: String) throws -> Date {
        for f in formatters {
            if let d = f.date(from: s) { return d }
        }
        throw BridgeError.invalidInput("Cannot parse date: \(s)")
    }

    static func formatISO(_ d: Date) -> String {
        outputFormatter.string(from: d)
    }
}

struct CalendarPayload: Encodable {
    let id: String
    let title: String
    let color: String
    let type: String
    let account: String
    let is_default: Bool
}

struct CalendarsPayload: Encodable {
    let calendars: [CalendarPayload]
    let count: Int
}

extension EventMapper {
    static func mapCalendar(_ cal: EKCalendar, defaultId: String?) -> CalendarPayload {
        CalendarPayload(
            id: cal.calendarIdentifier,
            title: cal.title,
            color: CalendarStore.hexColor(from: cal.cgColor),
            type: CalendarStore.typeString(cal.type),
            account: cal.source.title,
            is_default: cal.calendarIdentifier == defaultId
        )
    }
}
