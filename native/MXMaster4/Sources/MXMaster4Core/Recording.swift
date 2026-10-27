import Foundation

/// Replays the repository's existing JSON cassettes without copying their data.
public final class Recording: ReportTransport {
    private struct Cassette: Decodable {
        let schema_version: Int
        let name: String
        let report_support: String
        let exchanges: [Exchange]
    }
    private struct Exchange: Decodable {
        let request_match: String
        let request: String
        let response: String
        let required: Bool
    }
    private let cassette: Cassette
    private var position = 0
    public var name: String { cassette.name }
    public var longOnly: Bool { cassette.report_support == "long_only" }

    public init(url: URL) throws {
        cassette = try JSONDecoder().decode(Cassette.self, from: Data(contentsOf: url))
        guard cassette.schema_version == 1,
              ["short_and_long", "long_only"].contains(cassette.report_support),
              !cassette.exchanges.isEmpty else {
            throw HIDPPError.malformed("unsupported or empty cassette")
        }
        for entry in cassette.exchanges {
            guard ["exact", "hidpp20"].contains(entry.request_match) else {
                throw HIDPPError.malformed("unknown cassette match policy")
            }
            _ = try HIDPPReport([UInt8](hex: entry.request))
            _ = try HIDPPReport([UInt8](hex: entry.response))
        }
    }

    public func exchange(_ request: [UInt8]) throws -> [UInt8] {
        let actual = try HIDPPReport(request)
        while position < cassette.exchanges.count {
            let entry = cassette.exchanges[position]
            let expected = try HIDPPReport([UInt8](hex: entry.request))
            let matches: Bool
            if entry.request_match == "exact" {
                matches = actual == expected
            } else {
                matches = actual.device == expected.device && actual.feature == expected.feature
                    && actual.functionAndSoftwareID >> 4 == expected.functionAndSoftwareID >> 4
                    && padded(actual.payload) == padded(expected.payload)
            }
            if matches {
                position += 1
                var reply = try [UInt8](hex: entry.response)
                if entry.request_match == "hidpp20" {
                    // Error responses carry the original function/software byte in payload[0].
                    let offset = reply[2] == 0xff ? 4 : 3
                    reply[offset] = reply[offset] & 0xf0 | actual.functionAndSoftwareID & 0x0f
                }
                return reply
            }
            guard !entry.required else {
                throw HIDPPError.malformed("\(name): unexpected request at exchange \(position)")
            }
            position += 1
        }
        throw HIDPPError.exhaustedReplay
    }

    public func requireComplete() throws {
        guard !cassette.exchanges.dropFirst(position).contains(where: \.required) else {
            throw HIDPPError.malformed("\(name): required exchanges were not consumed")
        }
    }

    private func padded(_ payload: [UInt8]) -> [UInt8] {
        payload + Array(repeating: 0, count: 16 - payload.count)
    }
}

public enum RecordedMouse {
    public static let caseNames = ["feature-table", "reprogrammable-controls", "raw-battery",
        "dpi-info", "smartshift-status", "wheel-mode", "backlight-state"]

    public static func read(directory: URL) throws -> DiagnosticSnapshot {
        var mouse = MouseSnapshot(id: "recorded-mx-master-4", name: "MX Master 4",
            connection: "Recorded Bolt session", deviceIndex: 2)
        for name in caseNames {
            let recording = try Recording(url: directory.appendingPathComponent("cases/\(name).json"))
            guard recording.name == name else { throw HIDPPError.malformed("cassette name differs") }
            _ = try BoltReceiver(transport: recording).uniqueID()
            let reader = MouseReader(transport: recording, device: 2, longOnly: recording.longOnly)
            try reader.ping()
            switch name {
            case "feature-table": mouse.features = try reader.features()
            case "reprogrammable-controls": mouse.controls = try reader.controls()
            case "raw-battery": mouse.battery = try reader.battery()
            case "dpi-info": mouse.dpi = try reader.dpi()
            case "smartshift-status": mouse.smartShift = try reader.smartShift()
            case "wheel-mode": mouse.wheel = try reader.wheel()
            case "backlight-state":
                guard try reader.feature(0x1982) == nil else {
                    throw HIDPPError.malformed("recorded mouse unexpectedly exposes backlight")
                }
            default: throw HIDPPError.malformed("unhandled cassette")
            }
            try recording.requireComplete()
        }
        return DiagnosticSnapshot(recorded: true, inputMonitoringGranted: false, mice: [mouse], issues: [])
    }
}
