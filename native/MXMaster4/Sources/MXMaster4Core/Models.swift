import Foundation

public struct Feature: Codable, Equatable, Sendable, Identifiable {
    public let id: UInt16
    public let index: UInt8
    public let version: UInt8
    public let flags: UInt8
    public var hexID: String { String(format: "0x%04x", id) }
    public var name: String {
        switch id {
        case 0: "Root"
        case 1: "Feature Set"
        case 3: "Device Information"
        case 5: "Device Type and Name"
        case 7: "Friendly Name"
        case 0x1004: "Battery"
        case 0x1814: "Change Host"
        case 0x1815: "Hosts Info"
        case 0x19b0: "Haptic Feedback"
        case 0x19c0: "Force Sensing Button (not implemented)"
        case 0x1b04: "Reprogrammable Controls"
        case 0x1d4b: "Wireless Device Status"
        case 0x2111: "SmartShift Enhanced"
        case 0x2121: "High Resolution Wheel"
        case 0x2150: "Thumb Wheel"
        case 0x2201: "Adjustable DPI"
        default: "Uninterpreted feature"
        }
    }
}

public struct Control: Codable, Equatable, Sendable, Identifiable {
    public let id: UInt16
    public let taskID: UInt16
    public let flags: UInt16
    public var hexID: String { String(format: "0x%04x", id) }
    public var name: String {
        switch id {
        case 0x50: "Left click"
        case 0x51: "Right click"
        case 0x52: "Middle click"
        case 0x53: "Back"
        case 0x56: "Forward"
        case 0xc3: "Gesture button"
        case 0xc4: "Wheel mode button"
        case 0x1a0: "Haptic Sense Panel"
        case 0xd7: "Virtual gesture control"
        default: "Other control"
        }
    }
}

public struct DPIState: Codable, Equatable, Sendable {
    public let current: UInt16
    public let values: [UInt16]
}

public struct BatteryState: Codable, Equatable, Sendable {
    public let percentage: UInt8
    public let level: UInt8
    public let status: UInt8
    public var description: String {
        ["Discharging", "Charging", "Nearly full", "Full", "Charging slowly",
         "Invalid battery", "Thermal error", "Charging error"].enumerated()
            .first { $0.offset == Int(status) }?.element ?? "Unknown status"
    }
}

public struct SmartShiftState: Codable, Equatable, Sendable {
    public enum Mode: UInt8, Codable, Sendable { case freeSpin = 1, ratchet = 2 }
    public let mode: Mode
    public let autoDisengage: UInt8
    public let torque: UInt8?
}

public struct WheelState: Codable, Equatable, Sendable {
    /// Preserve the complete mode for the later read-modify-write migration.
    public let bytes: [UInt8]
    public var highResolution: Bool { (bytes.first ?? 0) & 2 != 0 }
    public var inverted: Bool { (bytes.first ?? 0) & 4 != 0 }
    public var diverted: Bool { (bytes.first ?? 0) & 1 != 0 }
}

public struct MouseIdentity: Codable, Equatable, Sendable {
    public let name: String
    public let modelIDs: [UInt16]
    public let unitID: String
    public var isMXMaster4: Bool { modelIDs.contains(0xb042) }
}

public struct MouseSnapshot: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var connection: String
    public var deviceIndex: UInt8
    public var features: [Feature] = []
    public var controls: [Control] = []
    public var dpi: DPIState?
    public var battery: BatteryState?
    public var smartShift: SmartShiftState?
    public var wheel: WheelState?
    public var issues: [String] = []

    public init(id: String, name: String, connection: String, deviceIndex: UInt8) {
        self.id = id; self.name = name; self.connection = connection; self.deviceIndex = deviceIndex
    }
}

public struct DiagnosticSnapshot: Codable, Sendable {
    public static let version = 1
    public var protocolVersion = Self.version
    public var recorded: Bool
    public var inputMonitoringGranted: Bool
    public var mice: [MouseSnapshot]
    public var issues: [String]
    public var timestamp = Date()

    public init(recorded: Bool, inputMonitoringGranted: Bool, mice: [MouseSnapshot], issues: [String]) {
        self.recorded = recorded; self.inputMonitoringGranted = inputMonitoringGranted
        self.mice = mice; self.issues = issues
    }

    public static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.protocolVersion == version else {
            throw HIDPPError.malformed("agent version differs; rebuild and restart both applications")
        }
        guard Set(value.mice.map(\.id)).count == value.mice.count,
              value.mice.allSatisfy({ mouse in
                  (mouse.wheel.map { $0.bytes.count == 3 } ?? true)
                  && (mouse.battery.map { $0.percentage <= 100 && [1, 2, 4, 8].contains($0.level) && $0.status <= 7 } ?? true)
                  && Set(mouse.features.map(\.id)).count == mouse.features.count
                  && Set(mouse.controls.map(\.id)).count == mouse.controls.count
              }) else { throw HIDPPError.malformed("invalid diagnostic snapshot") }
        return value
    }
}
