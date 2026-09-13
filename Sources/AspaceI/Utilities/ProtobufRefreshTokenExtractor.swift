import Foundation

enum ProtobufRefreshTokenExtractor {
    static func extract(from topic: Data) -> String? {
        lengthDelimitedFields(in: topic, number: 1).compactMap(extractFromEntry).first
    }

    private static func extractFromEntry(_ entry: Data) -> String? {
        guard stringField(in: entry, number: 1) == "oauthTokenInfoSentinelKey",
              let row = lengthDelimitedFields(in: entry, number: 2).first,
              let encodedInfo = stringField(in: row, number: 1),
              let info = Data(base64Encoded: encodedInfo) else {
            return nil
        }
        return stringField(in: info, number: 3)
    }

    private static func stringField(in data: Data, number: UInt64) -> String? {
        lengthDelimitedFields(in: data, number: number)
            .compactMap { String(data: $0, encoding: .utf8) }
            .first
    }

    private static func lengthDelimitedFields(in data: Data, number: UInt64) -> [Data] {
        let bytes = [UInt8](data)
        var offset = 0
        var result: [Data] = []
        while offset < bytes.count, let tag = readVarint(bytes, offset: &offset) {
            let fieldNumber = tag >> 3
            let wireType = tag & 7
            if wireType == 2, let length = readVarint(bytes, offset: &offset) {
                let count = Int(length)
                guard count >= 0, offset + count <= bytes.count else { return result }
                if fieldNumber == number {
                    result.append(Data(bytes[offset..<(offset + count)]))
                }
                offset += count
            } else if !skipField(bytes, wireType: wireType, offset: &offset) {
                return result
            }
        }
        return result
    }

    private static func readVarint(_ bytes: [UInt8], offset: inout Int) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while offset < bytes.count, shift < 64 {
            let byte = bytes[offset]
            offset += 1
            value |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        return nil
    }

    private static func skipField(_ bytes: [UInt8], wireType: UInt64, offset: inout Int) -> Bool {
        switch wireType {
        case 0:
            return readVarint(bytes, offset: &offset) != nil
        case 1:
            offset += 8
        case 5:
            offset += 4
        default:
            return false
        }
        return offset <= bytes.count
    }
}
