import Darwin
import Foundation
import MXMaster4Core

/// Compatible with openlogi-device/src/host_lock.rs and openlogi-hid's software-ID leases.
final class HostLock {
    private let descriptor: Int32
    private init(_ descriptor: Int32) { self.descriptor = descriptor }
    deinit { Darwin.close(descriptor) }

    static func nodeName(registryID: UInt64) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "RegistryEntryId(\(registryID))".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return String(format: "node-%016llx", hash)
    }

    static func take(_ name: String) throws -> HostLock? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("openlogi-locks")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(name).path
        let fd = Darwin.open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw HIDPPError.transport("Cannot open HID coordination lock: \(String(cString: strerror(errno)))") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            Darwin.close(fd)
            if code == EWOULDBLOCK { return nil }
            throw HIDPPError.transport("Cannot acquire HID coordination lock: \(String(cString: strerror(code)))")
        }
        return HostLock(fd)
    }

    static func softwareID(node: String) throws -> (UInt8, HostLock) {
        for id: UInt8 in 1...15 {
            if let lease = try take(String(format: "%@-sw-%02d", node, id)) { return (id, lease) }
        }
        throw HIDPPError.transport("All HID++ software IDs are in use. Close other OpenLogi diagnostics and refresh.")
    }
}
