// Bolt registers are reverse-engineered in openlogi-hidpp/src/receiver/bolt.rs (0BSD).
import Foundation

public struct BoltReceiver {
    private let transport: any ReportTransport
    public init(transport: any ReportTransport) { self.transport = transport }

    private func read(_ register: UInt8, _ parameters: [UInt8]) throws -> [UInt8] {
        let request = try HIDPPReport([0x10, 0xff, 0x83, register] + parameters)
        return try HIDPPReport(transport.exchange(request.bytes)).response(to: request)
    }

    public func uniqueID() throws -> String {
        let bytes = try read(0xfb, [0, 0, 0]).prefix { $0 != 0 }
        guard let uid = String(bytes: bytes, encoding: .utf8), !uid.isEmpty else {
            throw HIDPPError.malformed("invalid Bolt receiver identity")
        }
        return uid
    }

    public func pairedModel(slot: UInt8) throws -> UInt16 {
        guard (1...6).contains(slot) else { throw HIDPPError.malformed("invalid Bolt slot") }
        let p = try read(0xb5, [0x50 + slot, 0, 0])
        try p.require(4)
        guard p[0] == 0x50 + slot else { throw HIDPPError.unexpectedReply }
        return UInt16(p[2]) | UInt16(p[3]) << 8
    }
}
