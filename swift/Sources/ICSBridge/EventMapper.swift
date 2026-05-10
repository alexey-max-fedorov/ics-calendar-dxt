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
        f.timeZone = TimeZone.current
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

struct EventPayload: Encodable {
    let id: String
    let title: String
    let start: String
    let end: String
    let all_day: Bool
    let calendar_id: String
    let calendar_title: String
    let location: String?
    let notes: String?
    let url: String?
    let is_recurring: Bool
    let recurrence_rule: String?
}

struct EventsPayload: Encodable {
    let events: [EventPayload]
    let count: Int
    let truncated: Bool
}

struct EventWrapperPayload: Encodable {
    let event: EventPayload
}

extension EventMapper {
    static func mapEvent(_ ev: EKEvent) -> EventPayload {
        let urlStr: String? = ev.url?.absoluteString
        let recurrenceRule: String? = ev.hasRecurrenceRules ? "recurring" : nil
        return EventPayload(
            id: ev.calendarItemIdentifier,
            title: ev.title ?? "",
            start: formatISO(ev.startDate),
            end: formatISO(ev.endDate),
            all_day: ev.isAllDay,
            calendar_id: ev.calendar?.calendarIdentifier ?? "",
            calendar_title: ev.calendar?.title ?? "",
            location: (ev.location?.isEmpty == false) ? ev.location : nil,
            notes: (ev.notes?.isEmpty == false) ? ev.notes : nil,
            url: urlStr,
            is_recurring: ev.hasRecurrenceRules,
            recurrence_rule: recurrenceRule
        )
    }
}

struct AvailabilityBusyOut: Encodable {
    let start: String
    let end: String
    let title: String?
}

struct AvailabilityFreeOut: Encodable {
    let start: String
    let end: String
}

struct AvailabilityResultPayload: Encodable {
    let start: String
    let end: String
    let busy: [AvailabilityBusyOut]
    let free: [AvailabilityFreeOut]
}
