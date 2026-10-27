import SwiftUI
import ServiceManagement

struct DeviceView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let mouse = model.selectedMouse {
                    Panel(title: L("device.device_details"), icon: "mouse") {
                        detail(L("device.device"), mouse.name)
                        detail(L("device.connection"), mouse.connection)
                        if let battery = mouse.battery { detail(L("device.battery"), "\(battery.percentage)% · \(battery.description)") }
                        detail("HID++", "\(mouse.features.count) features · \(mouse.controls.count) controls")
                        Button("Diagnostics…") { model.showDiagnostics = true }
                    }
                    if mouse.features.contains(where: { $0.id == 0x1815 }) {
                        Panel(title: L("device.easy_switch"), icon: "monitor") {
                            Text("Channel information has not been read yet.").foregroundStyle(.secondary)
                            ForEach(1...3, id: \.self) { slot in
                                HStack(spacing: 12) {
                                    Text("\(slot)").font(.system(size: 16, weight: .semibold)).frame(width: 32, height: 32)
                                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                    Text(L("common.unavailable")).foregroundStyle(.secondary)
                                    Spacer()
                                }
                            }
                        }
                    }
                    Panel(title: L("device.configuration"), icon: "settings") {
                        Text(L("device.manage_this_device")).font(.system(size: 13, weight: .medium))
                        Text("This native build does not change the existing OpenLogi configuration.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button(L("profiles.reset_profile")) { model.resetProfile() }.disabled(!model.previewEditing)
                    }
                }
            }.padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
    }
    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).textSelection(.enabled).multilineTextAlignment(.trailing) }
    }
}

struct AgentSettings: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("MX Master 4 Native").font(.title2); Spacer(); Button(L("common.done")) { dismiss() } }
            Picker("Appearance", selection: $model.appearance) {
                Text("System").tag(ColorScheme?.none); Text("Light").tag(ColorScheme?.some(.light)); Text("Dark").tag(ColorScheme?.some(.dark))
            }.pickerStyle(.segmented)
            Divider()
            Text(model.statusText).font(.headline)
            Text("The agent reads the mouse and runs at login when enabled. Only the agent needs Input Monitoring.")
                .foregroundStyle(.secondary)
            HStack {
                if model.registered {
                    Button("Refresh") { Task { await model.refresh() } }
                    Button("Restart agent") { Task { await model.restart() } }
                    Button("Disable agent") { Task { await model.disable() } }
                } else { Button("Enable agent") { Task { await model.enable() } } }
                Button("Login Items…") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let snapshot = model.snapshot, !snapshot.recorded {
                Text(snapshot.inputMonitoringGranted ? "Input Monitoring: allowed" : "Input Monitoring: required")
                if !snapshot.inputMonitoringGranted {
                    Button("Request Input Monitoring…") { Task { await model.refresh(requestPermission: true) } }.disabled(!model.registered)
                }
                ForEach(Array(snapshot.issues.enumerated()), id: \.offset) { _, issue in Text(issue).font(.caption).textSelection(.enabled) }
            }
            if let error = model.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Divider()
            Button("Open hardware recording…") { model.chooseRecording() }
            Text("Preview changes remain in memory. Connecting to hardware replaces the preview.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 600).disabled(model.busy)
    }
}
