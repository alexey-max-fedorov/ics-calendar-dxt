import Foundation
import ArgumentParser

struct ICalBridge: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ical-bridge",
        abstract: "iCal Integration EventKit bridge",
        subcommands: [
            ListCalendars.self,
            GetEvents.self,
            SearchEvents.self,
            CreateEvent.self,
            UpdateEvent.self,
            DeleteEvent.self,
            GetAvailability.self
        ]
    )
}

struct StubCalendar: Encodable {
    let id: String
    let title: String
    let color: String
    let type: String
    let account: String
    let is_default: Bool
}

struct StubCalendarsPayload: Encodable {
    let calendars: [StubCalendar]
    let count: Int
}

struct StubEvent: Encodable {
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

struct StubEventsPayload: Encodable {
    let events: [StubEvent]
    let count: Int
    let truncated: Bool
}

struct StubEventWrapper: Encodable {
    let event: StubEvent
}

struct StubDeletePayload: Encodable {
    let deleted: Bool
    let id: String
}

struct StubAvailabilityBlock: Encodable {
    let start: String
    let end: String
    let title: String?
}

struct StubAvailabilityFreeBlock: Encodable {
    let start: String
    let end: String
}

struct StubAvailabilityPayload: Encodable {
    let start: String
    let end: String
    let busy: [StubAvailabilityBlock]
    let free: [StubAvailabilityFreeBlock]
}

extension ICalBridge {
    struct ListCalendars: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list-calendars")
        @Option var type: String = "event"
        func run() throws {
            let payload = StubCalendarsPayload(calendars: [], count: 0)
            OutputJSON.emit(BridgeResult.success(payload))
        }
    }

    struct GetEvents: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "get-events")
        @Option var start: String
        @Option var end: String
        @Option(name: .customLong("calendar-id")) var calendarId: String?
        @Flag(name: .customLong("no-all-day")) var noAllDay: Bool = false
        func run() throws {
            let payload = StubEventsPayload(events: [], count: 0, truncated: false)
            OutputJSON.emit(BridgeResult.success(payload))
        }
    }

    struct SearchEvents: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "search-events")
        @Option var query: String
        @Option var start: String?
        @Option var end: String?
        @Option(name: .customLong("calendar-id")) var calendarId: String?
        func run() throws {
            let payload = StubEventsPayload(events: [], count: 0, truncated: false)
            OutputJSON.emit(BridgeResult.success(payload))
        }
    }

    struct CreateEvent: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "create-event")
        @Option var title: String
        @Option var start: String
        @Option var end: String
        @Flag(name: .customLong("all-day")) var allDay: Bool = false
        @Option(name: .customLong("calendar-id")) var calendarId: String?
        @Option var location: String?
        @Option var notes: String?
        @Option var url: String?
        func run() throws {
            let stub = StubEvent(
                id: "stub-id",
                title: title,
                start: start,
                end: end,
                all_day: allDay,
                calendar_id: calendarId ?? "stub-cal",
                calendar_title: "Stub",
                location: location,
                notes: notes,
                url: url,
                is_recurring: false,
                recurrence_rule: nil
            )
            OutputJSON.emit(BridgeResult.success(StubEventWrapper(event: stub)))
        }
    }

    struct UpdateEvent: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "update-event")
        @Option var id: String
        @Option var title: String?
        @Option var start: String?
        @Option var end: String?
        @Option var location: String?
        @Option var notes: String?
        @Option var url: String?
        @Option(name: .customLong("calendar-id")) var calendarId: String?
        func run() throws {
            let stub = StubEvent(
                id: id,
                title: title ?? "stub",
                start: start ?? "2026-01-01T00:00:00Z",
                end: end ?? "2026-01-01T01:00:00Z",
                all_day: false,
                calendar_id: calendarId ?? "stub-cal",
                calendar_title: "Stub",
                location: location,
                notes: notes,
                url: url,
                is_recurring: false,
                recurrence_rule: nil
            )
            OutputJSON.emit(BridgeResult.success(StubEventWrapper(event: stub)))
        }
    }

    struct DeleteEvent: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "delete-event")
        @Option var id: String
        @Option var span: String = "this_only"
        func run() throws {
            OutputJSON.emit(BridgeResult.success(StubDeletePayload(deleted: true, id: id)))
        }
    }

    struct GetAvailability: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "get-availability")
        @Option var start: String
        @Option var end: String
        @Option(name: .customLong("calendar-ids")) var calendarIds: String?
        @Option var granularity: Int = 30
        func run() throws {
            let payload = StubAvailabilityPayload(start: start, end: end, busy: [], free: [])
            OutputJSON.emit(BridgeResult.success(payload))
        }
    }
}

ICalBridge.main()
