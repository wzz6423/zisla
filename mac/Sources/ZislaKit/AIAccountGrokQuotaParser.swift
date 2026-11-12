import Foundation
import ZislaCore

// Only descriptor-defined paths are quota fields; arbitrary protobuf floats are not balances.
enum AIAccountGrokQuotaParser {
    private struct Field {
        let number: UInt64
        var integer: UInt64?
        var float: Float?
        var message: Data?
    }

    /// Reads only descriptor-defined quota fields from one bounded, uncompressed gRPC-web payload.
    /// Protobuf's omitted scalar zero is accepted only for a confirmed active period with a future reset.
    static func parse(_ data: Data, now: Date) throws -> [AIAccountQuotaWindow] {
        guard !data.isEmpty, data.count <= 1_024 * 1_024 else { throw AIAccountBalanceError.invalidResponse }
        let bytes = [UInt8](data)
        var index = 0, payloads: [Data] = []
        while index < bytes.count {
            guard index + 5 <= bytes.count else { throw AIAccountBalanceError.invalidResponse }
            let flags = bytes[index]
            let size = bytes[(index + 1)...(index + 4)].reduce(0) { $0 * 256 + Int($1) }
            index += 5
            guard size <= bytes.count - index else { throw AIAccountBalanceError.invalidResponse }
            let body = Data(bytes[index..<(index + size)])
            if flags == 0 { payloads.append(body) }
            else if flags == 0x80 {
                guard let text = String(data: body, encoding: .utf8),
                      text.components(separatedBy: .newlines).filter({ $0.lowercased().hasPrefix("grpc-status:") })
                        .allSatisfy({ $0.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) == "0" }) else {
                    throw AIAccountBalanceError.invalidResponse
                }
            } else { throw AIAccountBalanceError.invalidResponse }
            index += size
        }
        guard payloads.count == 1 else { throw AIAccountBalanceError.invalidResponse }
        let root = try fields(payloads[0])
        let config = try message(root, number: 1)
        let percentage = try unique(config, number: 1)
        let reset = try timestamp(config, number: 5)
        let period = try optionalMessage(config, number: 8)
        let start = try period.flatMap { try timestamp($0, number: 2) }
        let end = try period.flatMap { try timestamp($0, number: 3) }
        let active = try period.flatMap { try unique($0, number: 1)?.integer }
        let used: Double
        if let percentage {
            guard let value = percentage.float, value.isFinite, (0...100).contains(value) else { throw AIAccountBalanceError.invalidResponse }
            used = Double(value)
        } else {
            guard active == 1 || active == 2, let start, let end, start <= now, now < end,
                  reset.map({ $0 > now }) == true else { throw AIAccountBalanceError.noQuota }
            used = 0
        }
        let duration = start.flatMap { begin in end.map { $0.timeIntervalSince(begin) } }.flatMap { $0 > 0 ? $0 : nil }
        let window = AIAccountQuotaWindow(id: "credits", kind: AIAccountBalanceParser.kind(duration: duration),
            remainingPercent: 100 - used, resetsAt: reset, durationSeconds: duration)
        guard window.isValid else { throw AIAccountBalanceError.invalidResponse }
        return [window]
    }

    /// An absent timestamp is optional; a present timestamp without its seconds field is malformed.
    private static func timestamp(_ fields: [Field], number: UInt64) throws -> Date? {
        guard let nested = try optionalMessage(fields, number: number) else { return nil }
        guard let seconds = try unique(nested, number: 1)?.integer else { throw AIAccountBalanceError.invalidResponse }
        return try AIAccountBalanceParser.date(Double(seconds))
    }

    /// Rejects duplicate scalar or message fields rather than choosing an ambiguous quota observation.
    private static func unique(_ fields: [Field], number: UInt64) throws -> Field? {
        let matches = fields.filter { $0.number == number }
        guard matches.count <= 1 else { throw AIAccountBalanceError.invalidResponse }
        return matches.first
    }

    /// Distinguishes an absent message from a present field encoded with the wrong wire type.
    private static func optionalMessage(_ values: [Field], number: UInt64) throws -> [Field]? {
        guard let field = try unique(values, number: number) else { return nil }
        guard let data = field.message else { throw AIAccountBalanceError.invalidResponse }
        return try fields(data)
    }

    /// Requires the descriptor's enclosing message before any nested number may be treated as quota.
    private static func message(_ values: [Field], number: UInt64) throws -> [Field] {
        guard let result = try optionalMessage(values, number: number) else { throw AIAccountBalanceError.invalidResponse }
        return result
    }

    /// Bounds decoded fields and validates wire lengths without recursively interpreting unrelated payloads.
    private static func fields(_ data: Data) throws -> [Field] {
        let bytes = [UInt8](data)
        var index = 0, fields: [Field] = []
        while index < bytes.count {
            guard fields.count < 256 else { throw AIAccountBalanceError.invalidResponse }
            let tag = try varint(bytes, index: &index)
            let number = tag >> 3
            guard number > 0 else { throw AIAccountBalanceError.invalidResponse }
            var field = Field(number: number)
            switch tag & 7 {
            case 0: field.integer = try varint(bytes, index: &index)
            case 1:
                guard bytes.count - index >= 8 else { throw AIAccountBalanceError.invalidResponse }
                index += 8
            case 2:
                let length = try varint(bytes, index: &index)
                guard length <= UInt64(bytes.count - index) else { throw AIAccountBalanceError.invalidResponse }
                field.message = Data(bytes[index..<(index + Int(length))])
                index += Int(length)
            case 5:
                guard bytes.count - index >= 4 else { throw AIAccountBalanceError.invalidResponse }
                let bits = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[index + $1]) << ($1 * 8) }
                field.float = Float(bitPattern: bits)
                index += 4
            default: throw AIAccountBalanceError.invalidResponse
            }
            fields.append(field)
        }
        return fields
    }

    /// Refuses truncated or overflowing 64-bit varints before their values can index frame slices.
    private static func varint(_ bytes: [UInt8], index: inout Int) throws -> UInt64 {
        var result: UInt64 = 0
        for shift in stride(from: 0, through: 63, by: 7) {
            guard index < bytes.count else { throw AIAccountBalanceError.invalidResponse }
            let byte = bytes[index]
            index += 1
            guard shift < 63 || byte <= 1 else { throw AIAccountBalanceError.invalidResponse }
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return result }
        }
        throw AIAccountBalanceError.invalidResponse
    }
}
