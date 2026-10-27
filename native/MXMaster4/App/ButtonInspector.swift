import SwiftUI

struct ButtonInspector: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme: scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(model.selectedControl.map { L($0.key) } ?? L("actions.button_inspector"))
                    .font(.system(size: 17, weight: .semibold))
                if let control = model.selectedControl {
                    if !model.previewEditing {
                        Text("Button assignments have not been loaded from the agent.").foregroundStyle(p.muted)
                    } else if control == .thumbwheel { ThumbwheelEditor(model: model) }
                    else {
                        if model.draft.gestures[control] != nil { GestureEditor(model: model) }
                        else { Text(L("actions.current_action")).font(.system(size: 12)).foregroundStyle(p.muted) }
                        if let action = model.selectedAssignment {
                            HStack(spacing: 10) {
                                ActionGlyph(name: action.icon, size: 22)
                                Text(action.label).font(.system(size: 15, weight: .medium)).lineLimit(3)
                                Spacer()
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(p.page, in: RoundedRectangle(cornerRadius: 6))
                        }
                        HStack {
                            Button(L("common.edit")) { model.actionLibraryOpen.toggle(); model.search = "" }
                            Button(L("profiles.reset_profile")) { model.resetControl() }.buttonStyle(.link)
                        }
                        if model.profileID == "default" {
                            Button(model.draft.gestures[control] == nil ? L("actions.use_gestures") : L("actions.use_a_single_action")) {
                                model.setGestures(model.draft.gestures[control] == nil)
                            }.buttonStyle(.link)
                        }
                        if model.canHoldToScroll {
                            Toggle(L("actions.hold_to_scroll_sideways"), isOn: Binding(
                                get: { model.draft.holdToScroll.contains(control) }, set: model.setHoldToScroll))
                                .toggleStyle(.switch).controlSize(.small)
                        }
                        if model.actionLibraryOpen { Divider(); ActionLibrary(model: model, ring: false) }
                    }
                } else {
                    ActionGlyph(name: "mouse-pointer-click", size: 32).foregroundStyle(p.muted).padding(.top, 40)
                    Text(L("profiles.select_device_button_description")).foregroundStyle(p.muted).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.background(p.panel)
    }
}

struct GestureEditor: View {
    @ObservedObject var model: AppModel
    private let positions: [(String, CGFloat, CGFloat)] = [("Up", 1, 0), ("Left", 0, 1), ("Click", 1, 1), ("Right", 2, 1), ("Down", 1, 2)]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("actions.gestures")).font(.system(size: 12)).foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                ForEach(positions, id: \.0) { direction, x, y in
                    Button {
                        model.gestureDirection = direction; model.actionLibraryOpen = false
                    } label: {
                        VStack(spacing: 5) {
                            let action = model.selectedControl.flatMap { model.draft.gestures[$0]?[direction] }
                            ActionGlyph(name: action?.icon ?? "ban", size: 18)
                            Text(L("common.\(direction.lowercased())")).font(.system(size: 10))
                        }.frame(width: 56, height: 42)
                    }.buttonStyle(ChoiceStyle(selected: model.gestureDirection == direction))
                        .frame(width: 80, height: 56).position(x: 40 + x * 86, y: 28 + y * 62)
                }
            }.frame(width: 252, height: 180)
        }
    }
}

struct ThumbwheelEditor: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("pointer.thumbwheel_sensitivity_description")).font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(Presentation.shared.thumbwheelPresets) { preset in
                Button { model.editDraft { $0.wheelPreset = preset.id } } label: {
                    HStack(spacing: 8) { ActionGlyph(name: "chevrons-right"); Text(L(preset.key)) }
                }.buttonStyle(ChoiceStyle(selected: model.draft.wheelPreset == preset.id))
            }
            Divider()
            Text(L("pointer.sensitivity"))
            Slider(value: Binding(get: { model.draft.thumbSensitivity }, set: { value in model.editDraft { $0.thumbSensitivity = value } }), in: Presentation.shared.sensitivity.range, step: 1)
                .accessibilityLabel(L("pointer.thumb_wheel_sensitivity"))
            Text(model.draft.thumbSensitivity, format: .number.precision(.fractionLength(0))).monospacedDigit()
        }
    }
}

struct ActionLibrary: View {
    @ObservedObject var model: AppModel
    let ring: Bool
    @State private var custom: CustomActionKind?
    private let categories = ["Editing", "Browser", "Media", "Mouse", "Dpi", "Scroll", "Navigation", "System"]
    private func categoryLabel(_ category: String) -> String {
        L(category == "Mouse" ? "device.mouse" : ["Dpi", "Scroll"].contains(category) ? "pointer.\(category.lowercased())" : "actions.\(category.lowercased())")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(L("actions.search_actions"), text: $model.search).textFieldStyle(.roundedBorder)
                .accessibilityLabel(L("actions.search_actions"))
            let actions = model.filteredActions(ring: ring)
            if actions.isEmpty { Text(L("actions.no_actions_found")).foregroundStyle(.secondary) }
            ForEach(categories, id: \.self) { category in
                let group = actions.filter { $0.category == category }
                if !group.isEmpty {
                    Text(categoryLabel(category)).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(.top, 4)
                    VStack(spacing: 1) {
                        ForEach(group) { action in
                            Button { model.assign(Assignment(id: action.id), toRing: ring) } label: {
                                HStack(spacing: 9) { ActionGlyph(name: action.icon); Text(L(action.key)).lineLimit(2) }
                            }.buttonStyle(ChoiceStyle(selected: selected?.id == action.id))
                        }
                    }
                }
            }
            Divider()
            ForEach(CustomActionKind.allCases) { kind in
                Button { custom = kind } label: {
                    HStack(spacing: 9) { ActionGlyph(name: kind.icon); Text(L(kind.key)) }
                }.buttonStyle(ChoiceStyle())
            }
        }.disabled(!model.previewEditing)
            .sheet(item: $custom) { kind in
                CustomActionEditor(kind: kind, dpiPresets: model.pointer.presets) { model.assign($0, toRing: ring) }
            }
    }
    private var selected: Assignment? { ring ? model.draft.ring[model.selectedRingSlot] : model.selectedAssignment }
}

enum CustomActionKind: String, CaseIterable, Identifiable {
    case shortcut, application, dpi, text, appleScript, shell, workflow
    var id: String { rawValue }
    var key: String {
        switch self {
        case .shortcut: "action_ring.custom_shortcut"
        case .application: "action_ring.open_application_or_folder"
        case .dpi: "pointer.dpi_presets"
        case .text: "actions.type_text_heading"
        case .appleScript: "actions.run_applescript_heading"
        case .shell: "actions.run_shell_command_heading"
        case .workflow: "actions.workflow_heading"
        }
    }
    var icon: String {
        switch self { case .shortcut: "keyboard"; case .application: "folder"; case .dpi: "gauge"; case .text: "pencil"; case .appleScript, .shell: "terminal"; case .workflow: "list-checks" }
    }
    var actionID: String {
        switch self { case .shortcut: "CustomShortcut"; case .application: "OpenApplication"; case .dpi: "SetDpiPreset"; case .text: "TypeText"; case .appleScript: "RunAppleScript"; case .shell: "RunShellCommand"; case .workflow: "Workflow" }
    }
}

struct WorkflowDraftStep: Identifiable, Equatable {
    let id = UUID()
    var kind = "TypeText"
    var value = ""
}

struct CustomActionEditor: View {
    let kind: CustomActionKind
    var dpiPresets: [Int] = []
    let save: (Assignment) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var shortcutMode = "CustomShortcut"
    @State private var dpiPreset = 0
    @State private var steps = [WorkflowDraftStep()]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { ActionGlyph(name: kind.icon, size: 22); Text(L(kind.key)).font(.title2) }
            switch kind {
            case .shortcut:
                ShortcutRecorder(value: $text).frame(height: 46)
                Picker("Mode", selection: $shortcutMode) {
                    Text(L("actions.shortcut_tap")).tag("CustomShortcut")
                    Text(L("actions.shortcut_hold")).tag("HoldShortcut")
                    Text("Hold modifiers, tap key").tag("TapKeyHoldingModifiers")
                }.pickerStyle(.segmented)
            case .application:
                TextField(L("action_ring.application_folder_path_or_url"), text: $text).textFieldStyle(.roundedBorder)
                Button(L("common.open") + "…") {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = true
                    if panel.runModal() == .OK, let url = panel.url { text = url.path }
                }
            case .dpi:
                Picker(L("pointer.dpi_presets"), selection: $dpiPreset) {
                    ForEach(dpiPresets.indices, id: \.self) { Text("\(L("common.preset")) \($0 + 1): \(dpiPresets[$0]) DPI").tag($0) }
                }
            case .workflow:
                ForEach($steps) { $step in
                    HStack {
                        Picker("Step", selection: $step.kind) {
                            Text("Text").tag("TypeText"); Text("Shortcut").tag("PressKey"); Text("Delay (ms)").tag("DelayMs")
                            Text("AppleScript").tag("RunAppleScript"); Text("Shell").tag("RunShellCommand")
                        }.frame(width: 150)
                        TextField("Value", text: $step.value)
                        Button { steps.removeAll { $0.id == step.id } } label: { ActionGlyph(name: "x") }
                    }
                }
                Button(L("actions.add_workflow_step")) { steps.append(WorkflowDraftStep()) }
            default:
                TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(height: 180)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.3)))
            }
            Text("Preview only. This action will not be executed.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer(); Button(L("common.cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("common.save")) {
                    if let assignment { save(assignment); dismiss() }
                }.keyboardShortcut(.defaultAction).disabled(assignment == nil)
            }
        }.padding(24).frame(width: 520)
    }
    private var assignment: Assignment? {
        if kind == .dpi { return dpiPresets.indices.contains(dpiPreset) ? Assignment(id: kind.actionID, payload: String(dpiPreset), iconOverride: kind.icon) : nil }
        if kind == .workflow {
            guard !steps.isEmpty, steps.allSatisfy({ !$0.value.isEmpty && ($0.kind != "DelayMs" || UInt32($0.value) != nil) }) else { return nil }
            let rows = steps.map { ["kind": $0.kind, "value": $0.value] }
            guard let data = try? JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]), let json = String(data: data, encoding: .utf8) else { return nil }
            return Assignment(id: kind.actionID, payload: json, iconOverride: kind.icon)
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if kind == .application {
            guard text.hasPrefix("/") || ["http", "https", "mailto"].contains(URL(string: text)?.scheme?.lowercased() ?? "") else { return nil }
        }
        return Assignment(id: kind == .shortcut ? shortcutMode : kind.actionID, payload: text, iconOverride: kind.icon)
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var value: String
    func makeNSView(context: Context) -> RecorderField {
        let field = RecorderField(); field.placeholderString = "Click here, then press a shortcut"
        field.isEditable = false; field.isBezeled = true; field.bezelStyle = .roundedBezel
        return field
    }
    func updateNSView(_ view: RecorderField, context: Context) { view.stringValue = value; view.record = { value = $0 } }
    final class RecorderField: NSTextField {
        var record: ((String) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else { return false }
            keyDown(with: event); return true
        }
        override func keyDown(with event: NSEvent) {
            if let label = Self.chord(event) { record?(label) }
        }
        static func chord(_ event: NSEvent) -> String? {
            let special: [UInt16: String] = [36: "Return", 48: "Tab", 49: "Space", 51: "Backspace", 53: "Escape", 123: "Left", 124: "Right", 125: "Down", 126: "Up"]
            guard let key = special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased(), !key.isEmpty else { return nil }
            let flags: [(NSEvent.ModifierFlags, String)] = [(.control, "Ctrl"), (.option, "Alt"), (.shift, "Shift"), (.command, "Cmd")]
            return (flags.compactMap { event.modifierFlags.contains($0.0) ? $0.1 : nil } + [key]).joined(separator: "+")
        }
    }
}
