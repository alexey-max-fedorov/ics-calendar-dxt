import Foundation
import EventKit

final class CalendarStore {
    let store = EKEventStore()

    func ensureAuthorization() throws {
        let status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            return
        case .authorized:
            return
        case .notDetermined:
            let sem = DispatchSemaphore(value: 0)
            var granted = false
            if #available(macOS 14.0, *) {
                store.requestFullAccessToEvents { ok, _ in
                    granted = ok
                    sem.signal()
                }
            } else {
                store.requestAccess(to: .event) { ok, _ in
                    granted = ok
                    sem.signal()
                }
            }
            sem.wait()
            if !granted {
                throw BridgeError.permissionDenied
            }
        case .denied, .restricted, .writeOnly:
            throw BridgeError.permissionDenied
        @unknown default:
            throw BridgeError.permissionDenied
        }
    }

    func eventCalendars(typeFilter: String) -> [EKCalendar] {
        let entity: EKEntityType = (typeFilter == "reminder") ? .reminder : .event
        let cals = store.calendars(for: entity)
        if typeFilter == "all" {
            return store.calendars(for: .event) + store.calendars(for: .reminder)
        }
        return cals
    }

    func calendar(byId id: String) -> EKCalendar? {
        if let c = store.calendar(withIdentifier: id) { return c }
        return store.calendars(for: .event).first(where: { $0.calendarIdentifier == id })
    }

    func event(byId id: String) -> EKEvent? {
        if let ev = store.event(withIdentifier: id) { return ev }
        if let item = store.calendarItem(withIdentifier: id) as? EKEvent { return item }
        return nil
    }

    static func typeString(_ t: EKCalendarType) -> String {
        switch t {
        case .local: return "local"
        case .calDAV: return "calDAV"
        case .exchange: return "exchange"
        case .subscription: return "subscription"
        case .birthday: return "birthday"
        @unknown default: return "local"
        }
    }

    static func hexColor(from cgColor: CGColor) -> String {
        guard let comps = cgColor.components, comps.count >= 3 else { return "#000000" }
        let r = Int((comps[0] * 255.0).rounded())
        let g = Int((comps[1] * 255.0).rounded())
        let b = Int((comps[2] * 255.0).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
