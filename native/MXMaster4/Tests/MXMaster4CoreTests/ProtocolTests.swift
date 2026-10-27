import Foundation
import Testing
@testable import MXMaster4Core

private let specimen: URL = {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    return root.appendingPathComponent("fixtures/devices/mx-master-4-001")
}()

@Test func allSevenHardwareRecordingsUseProductionReads() throws {
    let snapshot = try RecordedMouse.read(directory: specimen)
    let mouse = try #require(snapshot.mice.first)
    #expect(snapshot.recorded)
    #expect(mouse.dpi?.current == 2000)
    #expect(mouse.dpi?.values == Array(stride(from: UInt16(200), through: 8000, by: 50)))
    #expect(mouse.battery?.percentage == 40)
    #expect(mouse.battery?.status == 0)
    #expect(mouse.smartShift == SmartShiftState(mode: .ratchet, autoDisengage: 255, torque: 75))
    #expect(mouse.wheel == WheelState(bytes: [0, 0, 0]))
    #expect(mouse.features.count == 46)
    #expect(mouse.controls.count == 9)
    #expect(mouse.controls.first { $0.id == 0xc3 }?.taskID == 0x009c)
    #expect(mouse.controls.first { $0.id == 0x1a0 }?.taskID == 0x0109)
    #expect(mouse.controls.first { $0.id == 0x1a0 }?.flags == 0x0531)
    #expect(mouse.features.contains { $0.id == 0x19c0 })
    #expect(mouse.issues.isEmpty)
}

@Test func hardwareTablesMatchIndependentReviewedExpectations() throws {
    let snapshot = try RecordedMouse.read(directory: specimen)
    let mouse = try #require(snapshot.mice.first)
    let root = specimen.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    struct Expected: Decodable { let features: [[UInt16]]; let controls: [[UInt16]] }
    let url = root.appendingPathComponent("crates/openlogi-cli/src/cmd/fixture/record_case/corpus_diagnostics.json")
    let expected = try #require(JSONDecoder().decode([String: Expected].self, from: Data(contentsOf: url))["mx-master-4-001"])
    #expect(mouse.features.map { [$0.id, UInt16($0.version), UInt16($0.flags)] } == expected.features)
    #expect(mouse.controls.map { [$0.id, $0.taskID, $0.flags] } == expected.controls)
}

@Test(arguments: [[UInt8](), [0], [0xe0, 0x32, 0x1f, 0x40], [0x00, 0xc8, 0xe0, 0],
                  [0x00, 0xc8, 0xe0, 0x32], [0x00, 0xc8, 0xe0, 0x32, 0x00, 0x64]])
func malformedDPIRangesAreRejected(bytes: [UInt8]) {
    #expect(throws: HIDPPError.self) { try MouseReader.decodeDPIList(bytes) }
}

@Test func nonAlignedDPIEndpointIsIncluded() throws {
    #expect(try MouseReader.decodeDPIList([0, 200, 0xe0, 50, 1, 19, 0, 0]) == [200, 250, 275])
}

@Test func bluetoothRequestsUseLongReports() throws {
    let report = try HIDPPReport.request(device: 0xff, feature: 0, function: 0, softwareID: 3,
        payload: [0x22, 1, 0], long: true)
    #expect(report.bytes == [0x11, 0xff, 0, 3, 0x22, 1, 0] + Array(repeating: 0, count: 13))
}

@Test func repliesCannotCrossDevicesFunctionsOrSoftwareIDs() throws {
    let request = try HIDPPReport.request(device: 2, feature: 0x14, function: 2, softwareID: 3)
    for offset in [1, 2, 3] {
        var wrong = request.bytes; wrong[offset] ^= 1
        #expect(try !HIDPPReport(wrong).matches(request))
    }
    var notification = request.bytes; notification[3] &= 0xf0
    #expect(try !HIDPPReport(notification).matches(request))
    let error = try HIDPPReport([0x10, 2, 0xff, 0x14, 0x23, 7, 0])
    #expect(throws: HIDPPError.deviceError(7)) { try error.response(to: request) }
}

@Test func badFramesAndInvalidFunctionsFailBeforeSending() {
    for bytes: [UInt8] in [[], [0x10, 2], Array(repeating: 0, count: 20)] {
        #expect(throws: HIDPPError.self) { try HIDPPReport(bytes) }
    }
    #expect(throws: HIDPPError.self) {
        try HIDPPReport.request(device: 2, feature: 0, function: 16, softwareID: 1)
    }
    #expect(throws: HIDPPError.self) {
        try HIDPPReport.request(device: 2, feature: 0, function: 0, softwareID: 0)
    }
}

@Test func replayRequiresConsumptionAndRejectsWrongOrder() throws {
    let recording = try Recording(url: specimen.appendingPathComponent("cases/dpi-info.json"))
    #expect(throws: HIDPPError.self) { try recording.requireComplete() }
    #expect(throws: HIDPPError.self) { try MouseReader(transport: recording, device: 2).dpi() }
}

@Test func snapshotRoundTripRejectsProtocolSkew() throws {
    var snapshot = try RecordedMouse.read(directory: specimen)
    let decoded = try DiagnosticSnapshot.decode(JSONEncoder().encode(snapshot))
    #expect(decoded.mice.first?.controls == snapshot.mice.first?.controls)
    snapshot.protocolVersion += 1
    #expect(throws: HIDPPError.self) { try DiagnosticSnapshot.decode(JSONEncoder().encode(snapshot)) }
}

@Test func errorReportsUseTheOriginalRustProtocolVectors() throws {
    let request = try HIDPPReport.request(device: 1, feature: 7, function: 3, softwareID: 10)
    // openlogi-hidpp/src/protocol/v20.rs: an_error_naming_the_request_is_attributed_to_it.
    let error = try HIDPPReport([0x10, 1, 0xff, 7, 0x3a, 2, 0])
    #expect(throws: HIDPPError.deviceError(2)) { try error.response(to: request) }
    for offset in [1, 3, 4] {
        var wrong = error.bytes; wrong[offset] ^= 1
        #expect(try !HIDPPReport(wrong).matches(request))
    }
    let register = try HIDPPReport([0x10, 0xff, 0x83, 0xb5, 0x52, 0, 0])
    let unavailable = try HIDPPReport([0x10, 0xff, 0x8f, 0x83, 0xb5, 2, 0])
    #expect(throws: HIDPPError.deviceError(2)) { try unavailable.response(to: register) }
}

@Test func malformedSnapshotValuesAreRejected() throws {
    let valid = try JSONEncoder().encode(RecordedMouse.read(directory: specimen))
    var json = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
    var mice = try #require(json["mice"] as? [[String: Any]])
    mice[0]["wheel"] = ["bytes": []]
    json["mice"] = mice
    #expect(throws: HIDPPError.self) {
        try DiagnosticSnapshot.decode(JSONSerialization.data(withJSONObject: json))
    }
}
