import AppKit
import Security
import SwiftUI
import XCTest
import MXMaster4Core
import MXMaster4IPC
@testable import MXMaster4

final class WorkspaceTests: XCTestCase {
    @MainActor private func recordingModel() throws -> AppModel {
        let bundle = Bundle(for: Self.self)
        let fixture = try XCTUnwrap(bundle.resourceURL?.appendingPathComponent("mx-master-4-001"))
        let model = AppModel()
        model.accept(try RecordedMouse.read(directory: fixture))
        return model
    }

    @MainActor func testOriginalResourcesAndCatalogAreBundled() throws {
        let presentation = Presentation.shared
        XCTAssertEqual(presentation.actions.count, 45)
        XCTAssertEqual(presentation.ringDefaults, ["Cut", "Copy", "Paste", "BrowserForward", "PlayPause", "BrowserBack", "Undo", "Redo"])
        XCTAssertEqual(presentation.thumbwheelPresets.count, 14)
        for action in presentation.actions {
            XCTAssertNotEqual(presentation.text(action.key, locale: "en"), action.key)
            XCTAssertNotNil(NSImage(named: "ol-\(action.icon)"), action.icon)
        }
        for control in MouseControl.allCases {
            XCTAssertNotEqual(presentation.text(control.key, locale: "en"), control.key)
        }
        XCTAssertEqual(DeviceArt.image("side_core.png").size, CGSize(width: 656, height: 1024))
        XCTAssertEqual(presentation.text("device.buttons", locale: "ru-RU"), presentation.text("device.buttons", locale: "ru"))
    }

    @MainActor func testMetadataMarkersMatchActualDeviceAndFitBothWidths() throws {
        let art = DeviceArt.image("side_core.png")
        let size = CGSize(width: 1000, height: 600)
        let layout = DiagramLayout(size: size, pngSize: art.size, labels: true)
        XCTAssertEqual(Set(layout.markers.map(\.id)), Set(MouseControl.allCases))
        XCTAssertEqual(layout.markers.count, 7)
        let middle = try XCTUnwrap(layout.markers.first { $0.id == .middle })
        XCTAssertEqual((middle.point.x - layout.image.minX) / layout.image.width, (10 + 0.755 * 636) / 656, accuracy: 0.0001)
        XCTAssertEqual((middle.point.y - layout.image.minY) / layout.image.height, 0.19, accuracy: 0.0001)
        for width: CGFloat in [416, 530, 720, 1000] {
            let compact = DiagramLayout(size: CGSize(width: width, height: 500), pngSize: art.size, labels: true)
            for marker in compact.markers {
                XCTAssertTrue(compact.image.contains(marker.point))
                let label = try XCTUnwrap(marker.label)
                XCTAssertGreaterThanOrEqual(label.x - 78, 0)
                XCTAssertLessThanOrEqual(label.x + 78, width)
                XCTAssertGreaterThanOrEqual(label.y - 28, 0)
                XCTAssertLessThanOrEqual(label.y + 28, 500)
            }
            for side in [true, false] {
                let labels = compact.markers.filter { $0.left == side }.compactMap(\.label).sorted { $0.y < $1.y }
                for (first, second) in zip(labels, labels.dropFirst()) { XCTAssertGreaterThanOrEqual(second.y - first.y, 56) }
            }
        }
        let hidden = DiagramLayout(size: CGSize(width: 340, height: 500), pngSize: art.size, labels: false)
        XCTAssertTrue(hidden.markers.allSatisfy { $0.label == nil })
    }

    @MainActor func testSelectingControlsResetsEditorAndGestureDirection() throws {
        let model = try recordingModel()
        model.select(.gesture); model.gestureDirection = "Up"; model.actionLibraryOpen = true; model.search = "Copy"
        model.select(.haptic)
        XCTAssertEqual(model.gestureDirection, "Click")
        XCTAssertFalse(model.actionLibraryOpen)
        XCTAssertTrue(model.search.isEmpty)
        XCTAssertEqual(model.selectedAssignment?.id, "ShowActionsRing")
        model.setGestures(true); model.gestureDirection = "Left"; model.assign(Assignment(id: "Copy"))
        XCTAssertEqual(model.draft.gestures[.haptic]?["Left"]?.id, "Copy")
        XCTAssertEqual(model.draft.gestures[.haptic]?["Up"]?.id, "MissionControl")
        model.setGestures(false)
        XCTAssertEqual(model.selectedAssignment?.id, "ShowActionsRing")
    }

    @MainActor func testAppProfilesInheritAndOverrideWithoutLeaking() throws {
        let model = try recordingModel()
        model.addProfile(id: "com.example.Editor", name: "Editor")
        model.profileID = "default"; model.select(.middle); model.assign(Assignment(id: "Paste"))
        model.profileID = "com.example.Editor"
        XCTAssertEqual(model.selectedAssignment?.id, "Paste")
        model.assign(Assignment(id: "Copy"))
        model.profileID = "default"
        XCTAssertEqual(model.selectedAssignment?.id, "Paste")
        model.profileID = "com.example.Editor"
        model.resetControl()
        XCTAssertEqual(model.selectedAssignment?.id, "Paste")
        model.select(.gesture); model.assign(Assignment(id: "Cut"))
        XCTAssertNil(model.draft.gestures[.gesture])
        model.profileID = "default"
        XCTAssertEqual(model.draft.gestures[.gesture]?["Up"]?.id, "MissionControl")
    }

    @MainActor func testRingRejectsRecursiveActionsAndResetPreservesButtons() throws {
        let model = try recordingModel()
        model.select(.back); model.assign(Assignment(id: "Copy"))
        model.section = .ring; model.selectedRingSlot = 3
        for id in ["None", "ShowActionsRing"] { model.assign(Assignment(id: id), toRing: true) }
        XCTAssertEqual(model.draft.ring[3]?.id, "BrowserForward")
        model.assign(Assignment(id: "Save"), toRing: true)
        XCTAssertEqual(model.draft.ring[3]?.id, "Save")
        model.resetProfile()
        XCTAssertEqual(model.draft.ring[3]?.id, "BrowserForward")
        XCTAssertEqual(model.draft.bindings[.back]?.id, "Copy")
        model.search = ""
        XCTAssertFalse(model.filteredActions(ring: true).contains { ["None", "ShowActionsRing"].contains($0.id) })
    }

    @MainActor func testLiveSnapshotsCannotApplyPreviewChanges() throws {
        let model = try recordingModel()
        model.select(.middle); model.assign(Assignment(id: "Copy"))
        var live = try XCTUnwrap(model.snapshot); live.recorded = false
        model.accept(live); model.select(.middle)
        XCTAssertFalse(model.previewEditing)
        XCTAssertEqual(model.selectedAssignment?.id, "MiddleClick")
        model.assign(Assignment(id: "Cut")); model.setGestures(true)
        model.editPointer { $0.dpi = 5000 }
        model.addProfile(id: "com.example.Editor", name: "Editor")
        XCTAssertEqual(model.selectedAssignment?.id, "MiddleClick")
        XCTAssertEqual(model.pointer.dpi, 2000)
        XCTAssertEqual(model.profiles.count, 1)
    }

    @MainActor func testPointerReadsHardwareValuesAndSnapsToReportedDPI() throws {
        let model = try recordingModel()
        XCTAssertEqual(model.pointer.dpi, 2000)
        XCTAssertTrue(model.pointer.permanent)
        XCTAssertEqual(model.pointer.torque, 75)
        XCTAssertEqual(model.pointer.sensitivity, 16)
        XCTAssertEqual(model.pointer.verticalSensitivity, 14)
        XCTAssertEqual(model.draft.thumbSensitivity, 14)
        XCTAssertTrue(model.pointer.presets.isEmpty)
        model.editPointer { $0.dpi = 1033 }
        XCTAssertEqual(model.pointer.dpi, 1050)
        model.editPointer { $0.dpi = 99999 }
        XCTAssertEqual(model.pointer.dpi, 8000)
        XCTAssertEqual(model.snapshot?.mice.first?.dpi?.current, 2000)
    }

    @MainActor func testShortcutRecorderHandlesEventsInternally() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
                                                  windowNumber: 0, context: nil, characters: "P", charactersIgnoringModifiers: "p", isARepeat: false, keyCode: 35))
        let field = ShortcutRecorder.RecorderField()
        var recorded = ""
        field.record = { recorded = $0 }
        field.keyDown(with: event)
        XCTAssertEqual(recorded, "Shift+Cmd+P")
    }

    @MainActor func testEmbeddedAgentIdentityAndLaunchConfigurationAgree() throws {
        let main = Bundle.main
        let service = try AgentIdentity.serviceName(in: main)
        let url = main.bundleURL.appendingPathComponent(AgentIdentity.relativeBundle)
        let agent = try XCTUnwrap(Bundle(url: url))
        XCTAssertEqual(try AgentIdentity.serviceName(in: agent), service)
        XCTAssertEqual(agent.bundleIdentifier, service)
        let requirement = try AgentIdentity.requirement(for: url)
        var nativeRequirement: SecRequirement?
        XCTAssertEqual(SecRequirementCreateWithString(requirement as CFString, SecCSFlags(rawValue: 0), &nativeRequirement), errSecSuccess)
        var code: SecStaticCode?
        XCTAssertEqual(SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(rawValue: 0), &code), errSecSuccess)
        XCTAssertEqual(SecStaticCodeCheckValidity(try XCTUnwrap(code), SecCSFlags(rawValue: 0), nativeRequirement), errSecSuccess)
        var otherCode: SecStaticCode?
        XCTAssertEqual(SecStaticCodeCreateWithPath(main.bundleURL as CFURL, SecCSFlags(rawValue: 0), &otherCode), errSecSuccess)
        XCTAssertNotEqual(SecStaticCodeCheckValidity(try XCTUnwrap(otherCode), SecCSFlags(rawValue: 0), nativeRequirement), errSecSuccess)
        let plist = main.bundleURL.appendingPathComponent("Contents/Library/LaunchAgents/\(AgentIdentity.plistName)")
        let data = try Data(contentsOf: plist)
        let dict = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(dict["MachServices"] as? [String: Bool], [service: true])
        XCTAssertTrue(FileManager.default.fileExists(atPath: main.bundleURL.appendingPathComponent(try XCTUnwrap(dict["BundleProgram"] as? String)).path))
    }

    /// Renders the real SwiftUI tree inside the app process. No accessibility automation, screen capture or HID access.
    @MainActor func testRenderActualViewsInLightDarkAndNarrowWindows() throws {
        let output = URL(fileURLWithPath: "/tmp/openlogi-mx4-ui-renders", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let model = try recordingModel()
        let cases: [(String, DeviceSection, MouseControl?, Bool, ColorScheme, CGFloat)] = [
            ("buttons-light", .buttons, nil, false, .light, 1440),
            ("buttons-dark", .buttons, .haptic, false, .dark, 1280),
            ("gestures", .buttons, .gesture, false, .light, 1280),
            ("action-library", .buttons, .middle, true, .light, 1280),
            ("buttons-narrow", .buttons, .back, false, .light, 860),
            ("thumbwheel", .buttons, .thumbwheel, false, .dark, 1280),
            ("ring-light", .ring, nil, false, .light, 1280),
            ("ring-dark", .ring, nil, false, .dark, 1280),
            ("pointer-light", .pointer, nil, false, .light, 1280),
            ("pointer-narrow", .pointer, nil, false, .dark, 860),
            ("device", .device, nil, false, .light, 1280)
        ]
        for (name, section, control, library, scheme, width) in cases {
            model.section = section; model.selectedControl = control; model.actionLibraryOpen = library; model.appearance = scheme
            try render(ContentView(model: model), size: CGSize(width: width, height: 780), to: output.appendingPathComponent(name + ".png"))
        }
        model.showDevices = true
        try render(ContentView(model: model), size: CGSize(width: 1050, height: 780), to: output.appendingPathComponent("gallery.png"))
        model.snapshot = nil; model.error = "The agent is unavailable. Enable it in application settings."
        try render(ContentView(model: model), size: CGSize(width: 860, height: 650), to: output.appendingPathComponent("empty-error.png"))
    }

    @MainActor private func render<V: View>(_ view: V, size: CGSize, to url: URL) throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        // A never-shown window gives AppKit-backed SwiftUI controls a layout and appearance context.
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 15000, "Render is blank: \(url.lastPathComponent)")
        try png.write(to: url)
        let attachment = XCTAttachment(contentsOfFile: url)
        attachment.name = url.lastPathComponent; attachment.lifetime = .keepAlways
        add(attachment)
        window.close()
    }
}
