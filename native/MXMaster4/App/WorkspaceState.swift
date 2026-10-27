import AppKit
import UniformTypeIdentifiers
import SwiftUI
import MXMaster4Core

enum DeviceSection: String, CaseIterable, Identifiable {
    case buttons, ring, pointer, device
    var id: String { rawValue }
    var key: String {
        switch self {
        case .buttons: "device.buttons"
        case .ring: "action_ring.actions_ring"
        case .pointer: "device.pointer"
        case .device: "device.device"
        }
    }
    var icon: String {
        switch self { case .buttons: "mouse"; case .ring: "layout-grid"; case .pointer: "gauge"; case .device: "settings" }
    }
}

enum MouseControl: String, CaseIterable, Identifiable, Codable {
    case middle = "MiddleClick", mode = "DpiToggle", thumbwheel = "ThumbwheelRotation"
    case forward = "Forward", back = "Back", gesture = "GestureButton", haptic = "HapticPanel"
    var id: String { rawValue }
    var key: String {
        switch self {
        case .middle: "actions.middle_click"
        case .mode: "actions.dpi_toggle"
        case .thumbwheel: "pointer.thumb_wheel"
        case .forward: "actions.forward"
        case .back: "actions.back"
        case .gesture: "actions.gesture_button"
        case .haptic: "actions.haptic_panel"
        }
    }
    static func slot(_ name: String) -> Self? {
        switch name {
        case "SLOT_NAME_MIDDLE_BUTTON": .middle
        case "SLOT_NAME_MODESHIFT_BUTTON": .mode
        case "SLOT_NAME_THUMBWHEEL": .thumbwheel
        case "SLOT_NAME_FORWARD_BUTTON": .forward
        case "SLOT_NAME_BACK_BUTTON": .back
        case "SLOT_NAME_GESTURE_BUTTON": .gesture
        case "ASSIGNMENT_NAME_SHOW_RADIAL_MENU": .haptic
        default: nil
        }
    }
}

struct Assignment: Equatable {
    let id: String
    var payload = ""
    var iconOverride: String?
    var label: String {
        if payload.isEmpty { return Presentation.shared.action(id).map { L($0.key) } ?? id }
        switch id {
        case "SetDpiPreset": return L("pointer.dpi_preset").replacingOccurrences(of: "%{index}", with: String((Int(payload) ?? 0) + 1))
        case "RunAppleScript": return L("actions.run_applescript_heading")
        case "RunShellCommand": return L("actions.run_shell_command_heading")
        case "Workflow": return L("actions.workflow_heading")
        case "HoldShortcut": return L("actions.hold_shortcut").replacingOccurrences(of: "%{chord}", with: payload)
        default: return payload
        }
    }
    var icon: String { iconOverride ?? Presentation.shared.action(id)?.icon ?? (id == "OpenApplication" ? "grid-3x3" : "keyboard") }
}

struct ProfileDraft {
    var bindings: [MouseControl: Assignment] = [:]
    var gestures: [MouseControl: [String: Assignment]] = [:]
    var wheelPreset = "HorizontalScroll"
    var ring: [Int: Assignment] = [:]
    var ringEnabled = true
    var haptics = true
    var holdToScroll: Set<MouseControl> = []
    var thumbSensitivity = Presentation.shared.sensitivity.default
    var inheritedButtons: Set<MouseControl> = []
    var inheritsRing = false
    var inheritsWheel = false
    static var defaults: Self {
        var result = Self()
        let source = Presentation.shared
        for control in MouseControl.allCases where control != .thumbwheel {
            if let id = source.mouseDefaults[control.rawValue] { result.bindings[control] = Assignment(id: id) }
        }
        result.gestures[.gesture] = source.gestureDefaults.mapValues { Assignment(id: $0) }
        result.ring = Dictionary(uniqueKeysWithValues: source.ringDefaults.enumerated().map { ($0.offset, Assignment(id: $0.element)) })
        return result
    }
}

extension AppModel {
    var previewEditing: Bool { snapshot?.recorded == true }
    var draft: ProfileDraft {
        var value = profiles[profileID] ?? .defaults
        guard profileID != "default" else { return value }
        let base = profiles["default"] ?? .defaults
        for control in value.inheritedButtons {
            value.bindings[control] = base.bindings[control]
            value.gestures[control] = base.gestures[control]
            if base.holdToScroll.contains(control) { value.holdToScroll.insert(control) }
            else { value.holdToScroll.remove(control) }
        }
        if value.inheritsRing { value.ring = base.ring }
        if value.inheritsWheel { value.wheelPreset = base.wheelPreset; value.thumbSensitivity = base.thumbSensitivity }
        return value
    }
    func select(_ control: MouseControl) {
        selectedControl = control; actionLibraryOpen = false; search = ""; gestureDirection = "Click"
    }
    func editDraft(_ change: (inout ProfileDraft) -> Void) {
        guard previewEditing else { return }
        let previous = draft
        var value = previous; change(&value)
        if profileID != "default" {
            for control in MouseControl.allCases where value.bindings[control] != previous.bindings[control]
                || value.gestures[control] != previous.gestures[control]
                || value.holdToScroll.contains(control) != previous.holdToScroll.contains(control) {
                value.inheritedButtons.remove(control)
            }
            if value.ring != previous.ring { value.inheritsRing = false }
            if value.wheelPreset != previous.wheelPreset || value.thumbSensitivity != previous.thumbSensitivity { value.inheritsWheel = false }
        }
        profiles[profileID] = value
    }
    func assignment(for control: MouseControl) -> Assignment? {
        if control == .thumbwheel {
            guard let preset = Presentation.shared.thumbwheelPresets.first(where: { $0.id == draft.wheelPreset }) else { return nil }
            return Assignment(id: "WheelPreset", payload: L(preset.key), iconOverride: "chevrons-right")
        }
        if let gestures = draft.gestures[control], !gestures.isEmpty {
            return Assignment(id: "Gestures", payload: L("actions.five_directions"), iconOverride: "move")
        }
        return draft.bindings[control]
    }
    var selectedAssignment: Assignment? {
        guard let selectedControl else { return nil }
        return draft.gestures[selectedControl]?[gestureDirection] ?? draft.bindings[selectedControl]
    }
    func assign(_ action: Assignment, toRing: Bool = false) {
        guard previewEditing else { return }
        if toRing {
            guard action.id != "None", action.id != "ShowActionsRing", (0..<8).contains(selectedRingSlot) else { return }
            editDraft { $0.ring[selectedRingSlot] = action }
        } else if let control = selectedControl, control != .thumbwheel {
            editDraft {
                if profileID != "default" { $0.gestures[control] = nil; $0.bindings[control] = action }
                else if $0.gestures[control] != nil { $0.gestures[control]?[gestureDirection] = action }
                else { $0.bindings[control] = action }
            }
            actionLibraryOpen = false
        }
    }
    var canHoldToScroll: Bool {
        guard profileID == "default", let control = selectedControl, [.back, .forward].contains(control) else { return false }
        return selectedMouse?.controls.contains { $0.flags & 0x1000 != 0 } == true || draft.holdToScroll.contains(control)
    }
    func setHoldToScroll(_ enabled: Bool) {
        guard canHoldToScroll, let control = selectedControl else { return }
        editDraft {
            if enabled { $0.holdToScroll.insert(control); $0.gestures[control] = nil }
            else { $0.holdToScroll.remove(control) }
        }
    }
    func setGestures(_ enabled: Bool) {
        guard let control = selectedControl, control != .thumbwheel, profileID == "default" else { return }
        editDraft {
            $0.gestures[control] = enabled ? Presentation.shared.gestureDefaults.mapValues { Assignment(id: $0) } : nil
            if enabled { $0.holdToScroll.remove(control) }
        }
        gestureDirection = "Click"
    }
    func chooseProfileApplication() {
        guard previewEditing else { return }
        let panel = NSOpenPanel()
        panel.title = L("profiles.add_app_dialog")
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        addProfile(id: id, name: url.deletingPathExtension().lastPathComponent)
    }
    func addProfile(id: String, name: String) {
        guard previewEditing, !id.isEmpty, id != "default" else { return }
        if profiles[id] == nil {
            var value = ProfileDraft.defaults
            value.inheritedButtons = Set(MouseControl.allCases); value.inheritsRing = true; value.inheritsWheel = true
            profiles[id] = value
        }
        profileNames[id] = name
        profileID = id
    }
    func resetControl() {
        guard previewEditing, let control = selectedControl else { return }
        if profileID != "default" {
            profiles[profileID]?.inheritedButtons.insert(control)
            return
        }
        let defaults = ProfileDraft.defaults
        editDraft {
            $0.bindings[control] = defaults.bindings[control]
            $0.gestures[control] = defaults.gestures[control]
            $0.holdToScroll.remove(control)
        }
        gestureDirection = "Click"
    }
    func resetProfile() {
        guard previewEditing else { return }
        let defaults = ProfileDraft.defaults
        if section == .ring {
            if profileID == "default" { profiles[profileID]?.ring = defaults.ring }
            else { profiles[profileID]?.inheritsRing = true }
        } else {
            if profileID == "default" {
                profiles[profileID]?.bindings = defaults.bindings
                profiles[profileID]?.gestures = defaults.gestures
                profiles[profileID]?.wheelPreset = defaults.wheelPreset
                profiles[profileID]?.holdToScroll = []
            } else {
                profiles[profileID]?.inheritedButtons = Set(MouseControl.allCases)
                profiles[profileID]?.inheritsWheel = true
            }
        }
    }
    func removeProfile() {
        guard previewEditing, profileID != "default" else { return }
        profiles[profileID] = nil; profileNames[profileID] = nil; profileID = "default"
    }
    func filteredActions(ring: Bool) -> [Presentation.Action] {
        Presentation.shared.actions.filter { action in
            (!ring || (action.id != "None" && action.id != "ShowActionsRing"))
            && (search.isEmpty || L(action.key).localizedCaseInsensitiveContains(search) || action.category.localizedCaseInsensitiveContains(search))
        }
    }
}
