import SwiftUI
import MXMaster4Core

struct MouseDiagnostics: View {
    let mouse: MouseSnapshot
    var body: some View {
        Form {
            Section("Connection") {
                LabeledContent("Transport", value: mouse.connection)
                LabeledContent("HID++ device index", value: String(mouse.deviceIndex))
            }
            Section("Current values") {
                LabeledContent("DPI", value: mouse.dpi.map { String($0.current) } ?? "Unavailable")
                if let dpi = mouse.dpi, let first = dpi.values.first, let last = dpi.values.last {
                    LabeledContent("Supported DPI", value: "\(first)–\(last) · \(dpi.values.count) values")
                }
                if let battery = mouse.battery {
                    LabeledContent("Battery", value: "\(battery.percentage)% · \(battery.description)")
                }
                if let shift = mouse.smartShift {
                    LabeledContent("Wheel mode", value: shift.mode == .ratchet ? "Ratchet" : "Free spin")
                    LabeledContent("SmartShift threshold", value: shift.autoDisengage == 255 ? "Permanent ratchet" : String(shift.autoDisengage))
                    if let torque = shift.torque { LabeledContent("Ratchet torque", value: "\(torque)%") }
                }
                if let wheel = mouse.wheel {
                    LabeledContent("High resolution", value: wheel.highResolution ? "On" : "Off")
                    LabeledContent("Wheel inverted", value: wheel.inverted ? "Yes" : "No")
                    LabeledContent("Wheel reporting", value: wheel.diverted ? "HID++" : "Native HID")
                }
                Text("Read-only stage. Settings and button assignments arrive in later migration stages.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Controls · \(mouse.controls.count)") {
                ForEach(mouse.controls) { control in
                    LabeledContent(control.name) {
                        Text("\(control.hexID) · task \(hex(control.taskID)) · flags \(hex(control.flags))")
                            .monospaced().foregroundStyle(.secondary)
                    }
                }
            }
            Section("HID++ feature table · \(mouse.features.count)") {
                ForEach(mouse.features) { feature in
                    LabeledContent(feature.name) {
                        Text("\(feature.hexID) · index \(feature.index) · v\(feature.version) · flags \(feature.flags)")
                            .monospaced().foregroundStyle(.secondary)
                    }
                }
            }
            if !mouse.issues.isEmpty {
                Section("Read failures") {
                    ForEach(Array(mouse.issues.enumerated()), id: \.offset) { _, issue in Text(issue) }
                }
            }
        }.formStyle(.grouped).textSelection(.enabled)
    }
    private func hex(_ value: UInt16) -> String { String(format: "0x%04x", value) }
}
