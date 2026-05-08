import Foundation

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
