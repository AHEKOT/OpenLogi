import SwiftUI
import MXMaster4Core

struct PointerDraft: Equatable {
    var dpi = 2000.0
    var ratchet = true
    var permanent = false
    var sensitivity = Presentation.shared.smartShiftThreshold.default
    var torque = 50.0
    var inverted = false
    var resolution = "default"
    var smooth = false
    var smoothWheel = false
    var verticalSensitivity = Presentation.shared.sensitivity.default
    var presets: [Int] = []
    init(mouse: MouseSnapshot? = nil) {
        if let dpi = mouse?.dpi { self.dpi = Double(dpi.current) }
        if let shift = mouse?.smartShift {
            ratchet = shift.mode == .ratchet; permanent = shift.autoDisengage == 255
            let domain = Presentation.shared.smartShiftThreshold
            sensitivity = Double(shift.autoDisengage) < domain.min || shift.autoDisengage == 255
                ? domain.default : min(Double(shift.autoDisengage), domain.max)
            torque = Double(shift.torque ?? 50)
        }
        if let wheel = mouse?.wheel { inverted = wheel.inverted; resolution = wheel.highResolution ? "high" : "standard" }
    }
}

extension AppModel {
    func editPointer(_ update: (inout PointerDraft) -> Void) {
        guard previewEditing else { return }
        var value = pointer; update(&value)
        if let values = selectedMouse?.dpi?.values, !values.isEmpty,
           let nearest = values.min(by: { abs(Double($0) - value.dpi) < abs(Double($1) - value.dpi) }) {
            value.dpi = Double(nearest)
        }
        pointer = value
    }
}

struct PointerView: View {
    @ObservedObject var model: AppModel
    private func field<T>(_ path: WritableKeyPath<PointerDraft, T>) -> Binding<T> {
        Binding(get: { model.pointer[keyPath: path] }, set: { value in model.editPointer { $0[keyPath: path] = value } })
    }
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 332), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                dpiPanel
                shiftPanel
                scrollPanel
            }.padding(20).frame(maxWidth: 960).frame(maxWidth: .infinity)
        }
    }
    private var dpiPanel: some View {
        Panel(title: L("pointer.dpi"), icon: "gauge") {
            if let dpi = model.selectedMouse?.dpi, let min = dpi.values.first, let max = dpi.values.last, min < max {
                HStack { Text(L("pointer.dpi")).foregroundStyle(.secondary); Spacer(); Text("\(Int(model.pointer.dpi))").font(.title2).monospacedDigit() }
                Slider(value: field(\.dpi), in: Double(min)...Double(max)).accessibilityLabel(L("pointer.dpi"))
                HStack { Text("\(min)"); Spacer(); Text("\(max)") }.font(.caption).foregroundStyle(.secondary)
                Divider()
                Text(L("pointer.dpi_presets")).font(.system(size: 13, weight: .medium))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                    ForEach(model.pointer.presets.indices, id: \.self) { i in
                        HStack(spacing: 5) {
                            Button("\(model.pointer.presets[i])") { model.editPointer { $0.dpi = Double($0.presets[i]) } }.buttonStyle(.plain)
                            Button { model.editPointer { $0.presets.remove(at: i) } } label: { ActionGlyph(name: "x", size: 12) }.buttonStyle(.plain)
                        }.padding(7).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                    Button { model.editPointer { $0.presets.append(Int($0.dpi)) } } label: {
                        HStack(spacing: 5) { ActionGlyph(name: "square-plus", size: 14); Text(L("common.add")) }
                    }
                }
            } else { Text(L("pointer.dpi_range_device_offline")).foregroundStyle(.secondary) }
        }.disabled(!model.previewEditing)
    }
    private var shiftPanel: some View {
        Panel(title: L("pointer.smartshift"), icon: "rotate-cw") {
            if model.selectedMouse?.smartShift != nil {
                Picker(L("pointer.wheel_mode"), selection: field(\.ratchet)) {
                    Text(L("pointer.free_spin")).tag(false); Text(L("pointer.ratchet")).tag(true)
                }.pickerStyle(.segmented)
                Toggle(L("pointer.permanent_ratchet"), isOn: field(\.permanent)).toggleStyle(.switch).disabled(!model.pointer.ratchet)
                Text(L("pointer.never_auto_switch_to_free_spin")).font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(L("pointer.sensitivity")); Spacer(); Text("\(Int(model.pointer.sensitivity))") }
                    Slider(value: field(\.sensitivity), in: Presentation.shared.smartShiftThreshold.range, step: 1).accessibilityLabel(L("pointer.sensitivity"))
                    Text(L("pointer.smartshift_sensitivity_description")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.disabled(model.pointer.permanent || !model.pointer.ratchet)
                if model.selectedMouse?.smartShift?.torque != nil {
                    Divider()
                    HStack { Text(L("pointer.scrolling_force")); Spacer(); Text("\(Int(model.pointer.torque))%") }
                    Slider(value: field(\.torque), in: 1...100, step: 1).accessibilityLabel(L("pointer.scrolling_force"))
                    Text(L("pointer.scrolling_force_description")).font(.caption).foregroundStyle(.secondary)
                }
            } else { Text(L("pointer.this_device_does_not_support_smartshift")).foregroundStyle(.secondary) }
        }.disabled(!model.previewEditing)
    }
    private var scrollPanel: some View {
        Panel(title: L("pointer.scrolling"), icon: "scroll-text") {
            Toggle(L("pointer.invert_scroll_direction"), isOn: field(\.inverted)).toggleStyle(.switch)
            Text(L("pointer.scroll_direction_description")).font(.caption).foregroundStyle(.secondary)
            Picker(L("pointer.wheel_resolution"), selection: field(\.resolution)) {
                Text(L("pointer.device_default")).tag("default")
                Text(L("pointer.standard")).tag("standard")
                Text(L("pointer.high_resolution")).tag("high")
            }
            Text(L("pointer.high_resolution_scrolling_description")).font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle(L("pointer.smooth_scrolling"), isOn: field(\.smooth)).toggleStyle(.switch)
            Toggle(L("pointer.smooth_wheel"), isOn: field(\.smoothWheel)).toggleStyle(.switch)
            Text(L("pointer.smooth_wheel_description")).font(.caption).foregroundStyle(.secondary)
            HStack { Text(L("pointer.vertical_scroll_sensitivity")); Spacer(); Text(model.pointer.verticalSensitivity, format: .number.precision(.fractionLength(0))) }
            Slider(value: field(\.verticalSensitivity), in: Presentation.shared.sensitivity.range, step: 1).accessibilityLabel(L("pointer.vertical_scroll_sensitivity"))
        }.disabled(!model.previewEditing)
    }
}
