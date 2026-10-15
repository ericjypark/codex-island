import Foundation

// agy's SQLite metadata uses protobuf. Decode only wire fields needed for usage;
// reject truncated messages instead of interpreting partial bytes as zero tokens.
struct ProtobufFields {
    enum Value {
        case integer(UInt64)
        case bytes(Data)
        case fixed32(UInt32)
        case fixed64(UInt64)
    }
    let fields: [Int: [Value]]

    init?(_ data: Data) {
        let bytes = Array(data)
        var offset = 0
        var fields: [Int: [Value]] = [:]
        while offset < bytes.count {
            guard let tag = Self.varint(bytes, offset: &offset), tag >> 3 > 0,
                  tag >> 3 <= 536_870_911 else { return nil }
            let number = Int(tag >> 3)
            let value: Value
            switch tag & 7 {
            case 0:
                guard let n = Self.varint(bytes, offset: &offset) else { return nil }
                value = .integer(n)
            case 2:
                guard let length = Self.varint(bytes, offset: &offset),
                      length <= UInt64(bytes.count - offset) else { return nil }
                let end = offset + Int(length)
                value = .bytes(Data(bytes[offset..<end]))
                offset = end
            case 1, 5:
                let length = tag & 7 == 1 ? 8 : 4
                guard bytes.count - offset >= length else { return nil }
                var n: UInt64 = 0
                for i in 0..<length { n |= UInt64(bytes[offset + i]) << (8 * i) }
                offset += length
                value = length == 8 ? .fixed64(n) : .fixed32(UInt32(n))
            default: return nil
            }
            fields[number, default: []].append(value)
        }
        self.fields = fields
    }

    func integer(_ field: Int) -> Int? {
        guard case .integer(let value) = fields[field]?.last, value <= UInt64(Int.max) else { return nil }
        return Int(value)
    }

    func data(_ field: Int) -> Data? {
        guard case .bytes(let data) = fields[field]?.last else { return nil }
        return data
    }

    func message(_ field: Int) -> ProtobufFields? { data(field).flatMap(ProtobufFields.init) }
    func string(_ field: Int) -> String? { data(field).flatMap { String(data: $0, encoding: .utf8) } }

    func integers(_ field: Int) -> [Int]? {
        var result: [Int] = []
        for value in fields[field] ?? [] {
            switch value {
            case .integer(let n):
                guard n <= UInt64(Int.max) else { return nil }
                result.append(Int(n))
            case .bytes(let data):
                let bytes = Array(data)
                var offset = 0
                while offset < bytes.count {
                    guard let n = Self.varint(bytes, offset: &offset), n <= UInt64(Int.max) else { return nil }
                    result.append(Int(n))
                }
            default: return nil
            }
        }
        return result
    }

    var timestamp: Date? {
        guard let seconds = integer(1), seconds > 0 else { return nil }
        let nanos = integer(2) ?? 0
        guard nanos < 1_000_000_000 else { return nil }
        return Date(timeIntervalSince1970: Double(seconds) + Double(nanos) / 1_000_000_000)
    }

    private static func varint(_ bytes: [UInt8], offset: inout Int) -> UInt64? {
        var result: UInt64 = 0
        for shift in stride(from: 0, through: 63, by: 7) {
            guard offset < bytes.count else { return nil }
            let byte = bytes[offset]
            offset += 1
            if shift == 63 && byte > 1 { return nil }
            result |= UInt64(byte & 127) << shift
            if byte < 128 { return result }
        }
        return nil
    }
}
