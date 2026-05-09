import Foundation
import ArgumentParser
import EventKit

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

struct StubDeletePayload: Encodable {
    let deleted: Bool
    let id: String
}


extension ICalBridge {
    struct ListCalendars: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list-calendars")
        @Option var type: String = "event"
        func run() throws {
            do {
                let store = CalendarStore()
                try store.ensureAuthorization()
                let cals = store.eventCalendars(typeFilter: type)
                let defaultId = store.store.defaultCalendarForNewEvents?.calendarIdentifier
                let payload = CalendarsPayload(
                    calendars: cals.map { EventMapper.mapCalendar($0, defaultId: defaultId) },
                    count: cals.count
                )
                OutputJSON.emit(BridgeResult.success(payload))
            } catch let err as BridgeError {
                OutputJSON.emit(BridgeResult<CalendarsPayload>.error(err))
            } catch {
                OutputJSON.emit(BridgeResult<CalendarsPayload>.error(.internalError(String(describing: error))))
            }
        }
    }

    struct GetEvents: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "get-events")
        @Option var start: String
        @Option var end: String
        @Option(name: .customLong("calendar-id")) var calendarId: String?
        @Flag(name: .customLong("no-all-day")) var noAllDay: Bool = false

        func run() throws {
            do {
                let store = CalendarStore()
                try store.ensureAuthorization()
                let startDate = try EventMapper.parseISO(start)
                let endDate = try EventMapper.parseISO(end)
                if endDate <= startDate {
                    throw BridgeError.invalidInput("end must be after start")
                }
                let twoYears: TimeInterval = 60 * 60 * 24 * 365 * 2
                if endDate.timeIntervalSince(startDate) > twoYears {
                    throw BridgeError.invalidInput("Range exceeds 2 years; use a tighter range.")
                }
                let calendars: [EKCalendar]?
                if let cid = calendarId {
                    guard let cal = store.calendar(byId: cid) else {
                        throw BridgeError.notFound("calendar id \(cid)")
                    }
                    calendars = [cal]
                } else {
                    calendars = nil
                }
                let predicate = store.store.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
                let raw = store.store.events(matching: predicate)
                let filtered = raw.filter { !(noAllDay && $0.isAllDay) }
                let limit = 500
                let truncated = filtered.count > limit
                let trimmed = Array(filtered.prefix(limit))
                let payload = EventsPayload(
                    events: trimmed.map(EventMapper.mapEvent),
                    count: trimmed.count,
                    truncated: truncated
                )
                OutputJSON.emit(BridgeResult.success(payload))
            } catch let err as BridgeError {
                OutputJSON.emit(BridgeResult<EventsPayload>.error(err))
            } catch {
                OutputJSON.emit(BridgeResult<EventsPayload>.error(.internalError(String(describing: error))))
            }
        }
    }

    struct SearchEvents: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "search-events")
        @Option var query: String
        @Option var start: String?
        @Option var end: String?
        @Option(name: .customLong("calendar-id")) var calendarId: String?

        func run() throws {
            do {
                let store = CalendarStore()
                try store.ensureAuthorization()
                let now = Date()
                let startDate = try start.map { try EventMapper.parseISO($0) } ?? now.addingTimeInterval(-60*60*24*90)
                let endDate = try end.map { try EventMapper.parseISO($0) } ?? now.addingTimeInterval(60*60*24*365)
                if endDate <= startDate {
                    throw BridgeError.invalidInput("end must be after start")
                }
                let calendars: [EKCalendar]?
                if let cid = calendarId {
                    guard let cal = store.calendar(byId: cid) else {
                        throw BridgeError.notFound("calendar id \(cid)")
                    }
                    calendars = [cal]
                } else {
                    calendars = nil
                }
                let predicate = store.store.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
                let raw = store.store.events(matching: predicate)
                let needle = query.lowercased()
                let matched = raw.filter { ev in
                    let t = (ev.title ?? "").lowercased()
                    let l = (ev.location ?? "").lowercased()
                    let n = (ev.notes ?? "").lowercased()
                    return t.contains(needle) || l.contains(needle) || n.contains(needle)
                }
                let limit = 500
                let truncated = matched.count > limit
                let trimmed = Array(matched.prefix(limit))
                let payload = EventsPayload(
                    events: trimmed.map(EventMapper.mapEvent),
                    count: trimmed.count,
                    truncated: truncated
                )
                OutputJSON.emit(BridgeResult.success(payload))
            } catch let err as BridgeError {
                OutputJSON.emit(BridgeResult<EventsPayload>.error(err))
            } catch {
                OutputJSON.emit(BridgeResult<EventsPayload>.error(.internalError(String(describing: error))))
            }
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
            do {
                let store = CalendarStore()
                try store.ensureAuthorization()
                let startDate = try EventMapper.parseISO(start)
                let endDate = try EventMapper.parseISO(end)
                if endDate <= startDate {
                    throw BridgeError.invalidInput("end must be after start")
                }
                let cal: EKCalendar
                if let cid = calendarId {
                    guard let resolved = store.calendar(byId: cid) else {
                        throw BridgeError.notFound("calendar id \(cid)")
                    }
                    cal = resolved
                } else {
                    guard let def = store.store.defaultCalendarForNewEvents else {
                        throw BridgeError.notFound("no default calendar for new events")
                    }
                    cal = def
                }
                guard cal.allowsContentModifications else {
                    throw BridgeError.readOnly("calendar \(cal.title) does not allow modifications")
                }
                let ev = EKEvent(eventStore: store.store)
                ev.calendar = cal
                ev.title = title
                ev.startDate = startDate
                ev.endDate = endDate
                ev.isAllDay = allDay
                ev.location = location
                ev.notes = notes
                if let urlStr = url, let u = URL(string: urlStr) {
                    ev.url = u
                }
                do {
                    try store.store.save(ev, span: .thisEvent, commit: true)
                } catch {
                    throw BridgeError.saveFailed(error.localizedDescription)
                }
                let payload = EventWrapperPayload(event: EventMapper.mapEvent(ev))
                OutputJSON.emit(BridgeResult.success(payload))
            } catch let err as BridgeError {
                OutputJSON.emit(BridgeResult<EventWrapperPayload>.error(err))
            } catch {
                OutputJSON.emit(BridgeResult<EventWrapperPayload>.error(.internalError(String(describing: error))))
            }
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
            let stub = EventPayload(
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
            OutputJSON.emit(BridgeResult.success(EventWrapperPayload(event: stub)))
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
            do {
                let store = CalendarStore()
                try store.ensureAuthorization()
                let startDate = try EventMapper.parseISO(start)
                let endDate = try EventMapper.parseISO(end)
                if endDate <= startDate {
                    throw BridgeError.invalidInput("end must be after start")
                }
                let calendars: [EKCalendar]?
                if let csv = calendarIds, !csv.isEmpty {
                    let ids = csv.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                    var resolved: [EKCalendar] = []
                    for cid in ids {
                        guard let cal = store.calendar(byId: cid) else {
                            throw BridgeError.notFound("calendar id \(cid)")
                        }
                        resolved.append(cal)
                    }
                    calendars = resolved
                } else {
                    calendars = nil
                }
                let predicate = store.store.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
                let raw = store.store.events(matching: predicate).filter { !$0.isAllDay }
                let busy = raw.map { BusyInterval(start: $0.startDate, end: $0.endDate, title: $0.title) }
                let merged = Availability.merge(busy: busy, granularityMinutes: granularity)
                let free = Availability.freeBlocks(rangeStart: startDate, rangeEnd: endDate, merged: merged)
                let payload = AvailabilityResultPayload(
                    start: EventMapper.formatISO(startDate),
                    end: EventMapper.formatISO(endDate),
                    busy: merged.map { AvailabilityBusyOut(start: EventMapper.formatISO($0.start), end: EventMapper.formatISO($0.end), title: $0.title) },
                    free: free.map { AvailabilityFreeOut(start: EventMapper.formatISO($0.start), end: EventMapper.formatISO($0.end)) }
                )
                OutputJSON.emit(BridgeResult.success(payload))
            } catch let err as BridgeError {
                OutputJSON.emit(BridgeResult<AvailabilityResultPayload>.error(err))
            } catch {
                OutputJSON.emit(BridgeResult<AvailabilityResultPayload>.error(.internalError(String(describing: error))))
            }
        }
    }
}

ICalBridge.main()
