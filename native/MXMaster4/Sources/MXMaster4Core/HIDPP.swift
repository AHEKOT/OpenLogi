// Ported from openlogi-hidpp (0BSD); see THIRD_PARTY_NOTICES.md.
import Foundation

public enum HIDPPError: Error, LocalizedError, Equatable {
    case malformed(String)
    case unsupported(UInt16)
    case deviceError(UInt8)
    case timeout
    case disconnected
    case transport(String)
    case unexpectedReply
    case exhaustedReplay

    public var errorDescription: String? {
        switch self {
        case .malformed(let detail): "Invalid HID++ data: \(detail)"
        case .unsupported(let id): String(format: "Feature 0x%04x is not supported", id)
        case .deviceError(let code): String(format: "Device returned HID++ error 0x%02x", code)
        case .timeout: "The device did not respond. Wake the mouse and refresh."
        case .disconnected: "The device disconnected. Refresh to open a new connection."
        case .transport(let detail): detail
        case .unexpectedReply: "The device replied to a different request."
        case .exhaustedReplay: "The recording has no matching exchange."
        }
    }
}

/// Blocking operations belong on the agent's dedicated I/O queue, never its UI/run loop.
public protocol ReportTransport: AnyObject {
    func exchange(_ request: [UInt8]) throws -> [UInt8]
}

public struct HIDPPReport: Equatable, Sendable {
    public let bytes: [UInt8]
    public var device: UInt8 { bytes[1] }
    public var feature: UInt8 { bytes[2] }
    public var functionAndSoftwareID: UInt8 { bytes[3] }
    public var payload: [UInt8] { Array(bytes.dropFirst(4)) }

    public init(_ bytes: [UInt8]) throws {
        guard (bytes.count == 7 && bytes.first == 0x10)
            || (bytes.count == 20 && bytes.first == 0x11) else {
            throw HIDPPError.malformed("expected a 7-byte short or 20-byte long report")
        }
        self.bytes = bytes
    }

    public static func request(
        device: UInt8, feature: UInt8, function: UInt8, softwareID: UInt8,
        payload: [UInt8] = [0, 0, 0], long: Bool = false
    ) throws -> HIDPPReport {
        guard function < 16, (1...15).contains(softwareID), payload.count <= 16 else {
            throw HIDPPError.malformed("invalid function, software ID, or payload length")
        }
        let size = long || payload.count > 3 ? 20 : 7
        return try HIDPPReport(
            [size == 20 ? 0x11 : 0x10, device, feature, function << 4 | softwareID]
                + payload + Array(repeating: 0, count: size - 4 - payload.count)
        )
    }

    /// Notifications and replies for other callers must never complete this transaction.
    public func matches(_ request: HIDPPReport) -> Bool {
        guard device == request.device else { return false }
        if feature == 0x8f || feature == 0xff {
            return functionAndSoftwareID == request.feature && payload[0] == request.functionAndSoftwareID
        }
        return feature == request.feature && functionAndSoftwareID == request.functionAndSoftwareID
    }

    public func response(to request: HIDPPReport) throws -> [UInt8] {
        guard matches(request) else { throw HIDPPError.unexpectedReply }
        if feature == 0x8f || feature == 0xff { throw HIDPPError.deviceError(payload[1]) }
        return payload
    }
}

extension Array where Element == UInt8 {
    func require(_ count: Int) throws {
        guard self.count >= count else { throw HIDPPError.malformed("truncated payload") }
    }

    func word(at offset: Int) throws -> UInt16 {
        try require(offset + 2)
        return UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
    }

    public init(hex: String) throws {
        guard hex.count.isMultiple(of: 2), hex.utf8.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }) else { throw HIDPPError.malformed("invalid hexadecimal report") }
        self = []
        var position = hex.startIndex
        while position < hex.endIndex {
            let end = hex.index(position, offsetBy: 2)
            guard let value = UInt8(hex[position..<end], radix: 16) else {
                throw HIDPPError.malformed("invalid hexadecimal byte")
            }
            append(value)
            position = end
        }
    }
}
