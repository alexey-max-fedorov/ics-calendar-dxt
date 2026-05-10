import Foundation

struct BridgeResult<T: Encodable>: Encodable {
    let status: String
    let data: T?
    let error_code: String?
    let error_message: String?

    static func success(_ payload: T) -> BridgeResult<T> {
        BridgeResult(status: "success", data: payload, error_code: nil, error_message: nil)
    }

    static func error(_ err: BridgeError) -> BridgeResult<T> {
        BridgeResult(status: "error", data: nil, error_code: err.code, error_message: err.message)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        if let data = data {
            try container.encode(data, forKey: .data)
        } else {
            try container.encodeNil(forKey: .data)
        }
        if let code = error_code {
            try container.encode(code, forKey: .error_code)
        } else {
            try container.encodeNil(forKey: .error_code)
        }
        if let message = error_message {
            try container.encode(message, forKey: .error_message)
        } else {
            try container.encodeNil(forKey: .error_message)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case data
        case error_code
        case error_message
    }
}

enum OutputJSON {
    static func emit<T: Encodable>(_ result: BridgeResult<T>) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(result)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([0x0a]))
        } catch {
            let fallback = "{\"status\":\"error\",\"data\":null,\"error_code\":\"internal\",\"error_message\":\"JSON encode failed\"}\n"
            FileHandle.standardOutput.write(fallback.data(using: .utf8) ?? Data())
        }
    }

    static func logStderr(_ msg: String) {
        FileHandle.standardError.write((msg + "\n").data(using: .utf8) ?? Data())
    }
}
