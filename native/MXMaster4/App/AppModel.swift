import AppKit
import Combine
import MXMaster4Core
import MXMaster4IPC
import ServiceManagement
import SwiftUI

@MainActor final class AppModel: ObservableObject {
    @Published var snapshot: DiagnosticSnapshot?
    @Published var selectedID: String?
    @Published var busy = false
    @Published var error: String?
    @Published var serviceStatus = SMAppService.Status.notRegistered
    @Published var section = DeviceSection.buttons
    @Published var selectedControl: MouseControl?
    @Published var selectedRingSlot = 0
    @Published var actionLibraryOpen = false
    @Published var gestureDirection = "Click"
    @Published var search = ""
    @Published var profileID = "default"
    @Published var profiles: [String: ProfileDraft] = ["default": .defaults]
    @Published var profileNames: [String: String] = [:]
    @Published var showDevices = false
    @Published var showDiagnostics = false
    @Published var showAgentSettings = false
    @Published var appearance: ColorScheme?
    @Published var pointer = PointerDraft()
    private let service = SMAppService.agent(plistName: AgentIdentity.plistName)

    var selectedMouse: MouseSnapshot? { snapshot?.mice.first { $0.id == selectedID } }
    var registered: Bool { serviceStatus == .enabled }
    var statusText: String {
        switch serviceStatus {
        case .enabled: "Agent enabled"
        case .requiresApproval: "Agent needs approval in System Settings"
        case .notRegistered: "Agent disabled"
        case .notFound: "Agent bundle is missing"
        @unknown default: "Unknown agent status"
        }
    }

    func updateStatus() { serviceStatus = service.status }

    func refresh(requestPermission: Bool = false) async {
        await perform {
            let snapshot = try await AgentClient().snapshot(requestPermission: requestPermission)
            accept(snapshot)
        }
    }

    func enable() async {
        await perform {
            try service.register()
            updateStatus()
        }
        if registered { await refresh() }
    }

    func disable() async {
        await perform {
            try await service.unregister()
            updateStatus()
            snapshot = nil; selectedID = nil
        }
    }

    func restart() async {
        await perform {
            try await service.unregister()
            updateStatus()
            try service.register()
            updateStatus()
        }
        if registered { await refresh() }
    }

    func chooseRecording() {
        let panel = NSOpenPanel()
        panel.title = "Choose the mx-master-4-001 fixture folder"
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await replay(url) }
    }

    func replay(_ directory: URL) async {
        await perform {
            let snapshot = try await Task.detached { try RecordedMouse.read(directory: directory) }.value
            accept(snapshot)
        }
    }

    func accept(_ value: DiagnosticSnapshot) {
        let replacing = snapshot?.recorded != value.recorded || snapshot?.mice.map(\.id) != value.mice.map(\.id)
        snapshot = value
        if replacing {
            profiles = ["default": .defaults]; profileNames = [:]; profileID = "default"; selectedControl = nil
        }
        if !value.mice.contains(where: { $0.id == selectedID }) { selectedID = value.mice.first?.id }
        if replacing || !value.recorded { pointer = PointerDraft(mouse: selectedMouse) }
    }

    private func perform(_ operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false; updateStatus() }
        do { try await operation() }
        catch { self.error = error.localizedDescription }
    }
}
