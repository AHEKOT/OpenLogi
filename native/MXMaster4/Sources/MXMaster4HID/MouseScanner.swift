import Foundation
import IOKit
import IOKit.hid
import MXMaster4Core

public enum MouseScanner {
    public static var inputMonitoringGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Call only in the agent, on explicit user request; TCC can block this thread.
    public static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    public static func scan() -> DiagnosticSnapshot {
        guard inputMonitoringGranted else {
            return DiagnosticSnapshot(recorded: false, inputMonitoringGranted: false, mice: [], issues: [
                "Allow Input Monitoring for MX Master 4 Agent, then restart the agent."
            ])
        }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Int]] = [
            [kIOHIDVendorIDKey: 0x046d, kIOHIDDeviceUsagePageKey: 0xff00, kIOHIDDeviceUsageKey: 2],
            [kIOHIDVendorIDKey: 0x046d, kIOHIDDeviceUsagePageKey: 0xff43, kIOHIDDeviceUsageKey: 0x202],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        var mice: [MouseSnapshot] = []
        var issues: [String] = []
        for device in devices {
            let pid = number(device, kIOHIDProductIDKey)
            let isBolt = pid == 0xc548
            guard isBolt || pid == 0xb042 else { continue }
            do {
                let connection = try HIDConnection(device: device, registryID: registryID(device))
                try connection.open()
                defer { connection.close() }
                if isBolt {
                    let (uid, slots) = try pairedSlots(connection)
                    for slot in slots {
                        do {
                            let reader = MouseReader(transport: connection, device: slot, softwareID: connection.softwareID)
                            try reader.ping()
                            let identity = try reader.identity()
                            guard identity.isMXMaster4 else { continue }
                            mice.append(reader.snapshot(id: "bolt:\(uid):\(slot)", name: identity.name,
                                connection: "Logi Bolt · slot \(slot)"))
                        } catch HIDPPError.deviceError(let code) where code == 2 || code == 8 {
                            // An empty receiver register or sleeping slot is not a transport failure.
                            continue
                        } catch {
                            issues.append("Bolt slot \(slot): \(error.localizedDescription)")
                            if case HIDPPError.timeout = error { break }
                            if case HIDPPError.disconnected = error { break }
                        }
                    }
                } else {
                    let longOnly = number(device, kIOHIDDeviceUsagePageKey) == 0xff43
                    let reader = MouseReader(transport: connection, device: 0xff,
                        softwareID: connection.softwareID, longOnly: longOnly)
                    try reader.ping()
                    let identity = try reader.identity()
                    guard identity.isMXMaster4 else { continue }
                    mice.append(reader.snapshot(id: "direct:\(registryID(device))", name: identity.name,
                        connection: "Bluetooth"))
                }
            } catch { issues.append(error.localizedDescription) }
        }
        return DiagnosticSnapshot(recorded: false, inputMonitoringGranted: true,
            mice: mice.sorted { $0.id < $1.id }, issues: issues)
    }

    private static func pairedSlots(_ connection: HIDConnection) throws -> (String, [UInt8]) {
        guard let phase = try HostLock.take(connection.nodeName) else {
            throw HIDPPError.transport("Another OpenLogi process is reading this receiver. Refresh when it finishes.")
        }
        return try withExtendedLifetime(phase) {
            let bolt = BoltReceiver(transport: connection)
            let uid = try bolt.uniqueID()
            var slots: [UInt8] = []
            for slot: UInt8 in 1...6 {
                do { if try bolt.pairedModel(slot: slot) == 0xb042 { slots.append(slot) } }
                catch HIDPPError.deviceError(let code) where code == 2 || code == 8 { continue }
            }
            return (uid, slots)
        }
    }

    private static func number(_ device: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
    }

    private static func registryID(_ device: IOHIDDevice) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
        return id
    }
}
