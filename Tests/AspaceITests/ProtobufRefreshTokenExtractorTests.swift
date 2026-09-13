import Foundation
import Testing
@testable import AspaceI

struct ProtobufRefreshTokenExtractorTests {
    @Test
    func extractsRefreshTokenFromUnifiedStateTopic() throws {
        let tokenInfo = field(number: 3, value: Data("refresh-example".utf8))
        let row = field(number: 1, value: Data(tokenInfo.base64EncodedString().utf8))
        let entry = field(number: 1, value: Data("oauthTokenInfoSentinelKey".utf8))
            + field(number: 2, value: row)
        let topic = field(number: 1, value: entry)

        #expect(ProtobufRefreshTokenExtractor.extract(from: topic) == "refresh-example")
    }

    private func field(number: UInt8, value: Data) -> Data {
        var data = Data([number << 3 | 2])
        data.append(contentsOf: varint(value.count))
        data.append(value)
        return data
    }

    private func varint(_ value: Int) -> [UInt8] {
        var remaining = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(remaining & 0x7f)
            remaining >>= 7
            if remaining > 0 { byte |= 0x80 }
            bytes.append(byte)
        } while remaining > 0
        return bytes
    }
}
