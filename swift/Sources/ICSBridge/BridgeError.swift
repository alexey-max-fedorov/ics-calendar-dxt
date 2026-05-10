enum BridgeError: Error {
    case permissionDenied
    case notFound(String)
    case invalidInput(String)
    case readOnly(String)
    case saveFailed(String)
    case internalError(String)

    var code: String {
        switch self {
        case .permissionDenied: return "permission_denied"
        case .notFound: return "not_found"
        case .invalidInput: return "invalid_input"
        case .readOnly: return "read_only"
        case .saveFailed: return "save_failed"
        case .internalError: return "internal"
        }
    }

    var message: String {
        switch self {
        case .permissionDenied:
            return "Calendar access denied. Grant access in System Settings, Privacy and Security, Calendars."
        case .notFound(let detail): return "Not found: \(detail)"
        case .invalidInput(let detail): return "Invalid input: \(detail)"
        case .readOnly(let detail): return "Calendar is read-only: \(detail)"
        case .saveFailed(let detail): return "Save failed: \(detail)"
        case .internalError(let detail): return "Internal error: \(detail)"
        }
    }
}
