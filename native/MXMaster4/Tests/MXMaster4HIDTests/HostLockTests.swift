import Foundation
import Testing
@testable import MXMaster4HID

@Test func leasesExcludeConcurrentChannelsAndReleaseOnClose() throws {
    let node = "test-native-\(UUID().uuidString)"
    var first: (UInt8, HostLock)? = try HostLock.softwareID(node: node)
    #expect(first?.0 == 1)
    let second = try HostLock.softwareID(node: node)
    #expect(second.0 == 2)
    first = nil
    let reused = try HostLock.softwareID(node: node)
    #expect(reused.0 == 1)
    withExtendedLifetime((second, reused)) {}
}

@Test func registerPhaseCannotBeHeldTwice() throws {
    let name = "test-native-register-\(UUID().uuidString)"
    let held = try #require(try HostLock.take(name))
    #expect(try HostLock.take(name) == nil)
    withExtendedLifetime(held) {}
}
