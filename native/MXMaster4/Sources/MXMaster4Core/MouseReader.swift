// Protocol offsets follow the corresponding openlogi-hidpp feature modules (0BSD).
import Foundation

/// One synchronous reader per channel; the owner serializes complete operations.
public final class MouseReader {
    private let transport: any ReportTransport
    private let device: UInt8
    private let softwareID: UInt8
    private let longOnly: Bool

    public init(transport: any ReportTransport, device: UInt8, softwareID: UInt8 = 1, longOnly: Bool = false) {
        self.transport = transport; self.device = device
        self.softwareID = softwareID; self.longOnly = longOnly
    }

    private func call(_ feature: UInt8, _ function: UInt8, _ payload: [UInt8] = [0, 0, 0], long: Bool = false) throws -> [UInt8] {
        let request = try HIDPPReport.request(device: device, feature: feature, function: function,
            softwareID: softwareID, payload: payload, long: longOnly || long)
        let response = try HIDPPReport(transport.exchange(request.bytes))
        return try response.response(to: request)
    }

    public func ping() throws {
        let payload = try call(0, 1)
        try payload.require(2)
        guard payload[0] >= 2 else { throw HIDPPError.malformed("HID++ 2.0 or newer is required") }
    }

    public func feature(_ id: UInt16) throws -> Feature? {
        let p = try call(0, 0, [UInt8(id >> 8), UInt8(id & 0xff), 0])
        try p.require(3)
        return p[0] == 0 ? nil : Feature(id: id, index: p[0], version: p[2], flags: p[1])
    }

    private func requireFeature(_ id: UInt16) throws -> Feature {
        guard let found = try feature(id) else { throw HIDPPError.unsupported(id) }
        return found
    }

    public func features() throws -> [Feature] {
        let set = try requireFeature(1)
        let count = try call(set.index, 0)[0]
        return try (0...Int(count)).map { index in
            let p = try call(set.index, 1, [UInt8(index), 0, 0])
            try p.require(4)
            return Feature(id: try p.word(at: 0), index: UInt8(index), version: p[3], flags: p[2])
        }
    }

    public func controls() throws -> [Control] {
        let f = try requireFeature(0x1b04)
        let count = try call(f.index, 0)[0]
        return try (0..<count).map { index in
            let p = try call(f.index, 1, [index, 0, 0], long: true)
            try p.require(9)
            return Control(id: try p.word(at: 0), taskID: try p.word(at: 2),
                flags: UInt16(p[4]) | UInt16(p[8]) << 8)
        }
    }

    public func dpi() throws -> DPIState {
        let f = try requireFeature(0x2201)
        guard try call(f.index, 0)[0] > 0 else { throw HIDPPError.malformed("no DPI sensor") }
        let current = try call(f.index, 2).word(at: 1)
        let list = try call(f.index, 1)
        guard list[0] == 0 else { throw HIDPPError.malformed("DPI sensor echo differs") }
        return DPIState(current: current, values: try Self.decodeDPIList(Array(list.dropFirst())))
    }

    public static func decodeDPIList(_ bytes: [UInt8]) throws -> [UInt16] {
        var values: [UInt16] = []
        var offset = 0
        while offset + 1 < bytes.count {
            let value = try bytes.word(at: offset)
            if value == 0 { break }
            if value & 0xe000 == 0xe000 {
                let step = value & 0x1fff
                guard let start = values.last, step > 0 else {
                    throw HIDPPError.malformed("DPI range has no start or a zero step")
                }
                let end = try bytes.word(at: offset + 2)
                guard end >= start, end & 0xe000 != 0xe000 else {
                    throw HIDPPError.malformed("invalid DPI range endpoint")
                }
                var next = UInt32(start) + UInt32(step)
                while next < UInt32(end) {
                    values.append(UInt16(next)); next += UInt32(step)
                }
                values.append(end)
                offset += 4
            } else {
                values.append(value); offset += 2
            }
        }
        guard !values.isEmpty else { throw HIDPPError.malformed("empty DPI list") }
        return Array(Set(values)).sorted()
    }

    public func battery() throws -> BatteryState {
        let f = try requireFeature(0x1004)
        let p = try call(f.index, 1)
        try p.require(3)
        guard p[0] <= 100, [1, 2, 4, 8].contains(p[1]), p[2] <= 7 else {
            throw HIDPPError.malformed("unknown battery value")
        }
        return BatteryState(percentage: p[0], level: p[1], status: p[2])
    }

    public func smartShift() throws -> SmartShiftState {
        let f = try requireFeature(0x2111)
        let p = try call(f.index, 1)
        try p.require(3)
        guard let mode = SmartShiftState.Mode(rawValue: p[0]), p[2] <= 100 else {
            throw HIDPPError.malformed("invalid SmartShift mode or torque")
        }
        return SmartShiftState(mode: mode, autoDisengage: p[1], torque: p[2] == 0 ? nil : p[2])
    }

    public func wheel() throws -> WheelState {
        let f = try requireFeature(0x2121)
        let p = try call(f.index, 1)
        try p.require(3)
        return WheelState(bytes: Array(p.prefix(3)))
    }

    public func identity() throws -> MouseIdentity {
        let f = try requireFeature(3)
        let p = try call(f.index, 0)
        try p.require(15)
        let ids = try [7, 9, 11].map { try p.word(at: $0) }.filter { $0 != 0 }
        let unit = p[1...4].map { String(format: "%02x", $0) }.joined()
        let n = try requireFeature(5)
        let length = Int(try call(n.index, 0)[0])
        var name: [UInt8] = []
        while name.count < length {
            let chunk = try call(n.index, 1, [UInt8(name.count), 0, 0])
            name.append(contentsOf: chunk.prefix(length - name.count))
        }
        guard let decoded = String(bytes: name, encoding: .utf8), !decoded.isEmpty else {
            throw HIDPPError.malformed("invalid device name")
        }
        return MouseIdentity(name: decoded, modelIDs: ids, unitID: unit)
    }

    public func snapshot(id: String, name: String, connection: String) -> MouseSnapshot {
        var result = MouseSnapshot(id: id, name: name, connection: connection, deviceIndex: device)
        func read<T>(_ label: String, _ operation: () throws -> T) -> T? {
            do { return try operation() }
            catch { result.issues.append("\(label): \(error.localizedDescription)"); return nil }
        }
        result.features = read("Features", features) ?? []
        result.controls = read("Controls", controls) ?? []
        result.dpi = read("DPI", dpi)
        result.battery = read("Battery", battery)
        result.smartShift = read("SmartShift", smartShift)
        result.wheel = read("Wheel", wheel)
        return result
    }
}
