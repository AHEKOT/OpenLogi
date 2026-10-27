import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme: scheme)
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                Divider()
                if let error = model.error {
                    HStack {
                        Text(error).textSelection(.enabled)
                        Spacer()
                        Button(L("common.clear")) { model.error = nil }
                    }.font(.system(size: 12)).padding(12).background(Color.red.opacity(0.08))
                }
                if model.showDevices || model.selectedMouse == nil { gallery }
                else {
                    HStack(spacing: 0) {
                        rail
                        Divider()
                        VStack(spacing: 0) {
                            if model.section == .buttons || model.section == .ring { profileBar; Divider() }
                            switch model.section {
                            case .buttons:
                                HStack(spacing: 0) {
                                    VStack(spacing: 0) {
                                        if geometry.size.width < 960 {
                                            Picker(L("device.buttons"), selection: Binding(get: { model.selectedControl ?? .middle }, set: model.select)) {
                                                ForEach(MouseControl.allCases) { Text(L($0.key)).tag($0) }
                                            }.padding(16)
                                        }
                                        MouseDiagram(model: model, showLabels: geometry.size.width >= 960)
                                            .padding(12)
                                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                                    Divider()
                                    ButtonInspector(model: model).frame(width: Layout.inspector)
                                }
                            case .ring: ActionRingEditor(model: model)
                            case .pointer: PointerView(model: model)
                            case .device: DeviceView(model: model)
                            }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    Divider()
                    HStack(spacing: 8) {
                        Circle().fill(model.previewEditing ? p.accent : p.muted).frame(width: 6, height: 6)
                        Text(model.previewEditing
                             ? "Recorded session · sample assignments · edits stay in this preview"
                             : "Device values are read-only · assignment runtime is not connected yet")
                        Spacer(minLength: 0)
                        Button("Diagnostics") { model.showDiagnostics = true }.buttonStyle(.plain)
                    }.font(.system(size: 11)).foregroundStyle(p.muted).padding(.horizontal, 16).frame(height: 30)
                }
            }.background(p.page).foregroundStyle(p.text).font(.system(size: 13))
        }
        .sheet(isPresented: $model.showAgentSettings) { AgentSettings(model: model) }
        .sheet(isPresented: $model.showDiagnostics) {
            VStack(spacing: 0) {
                HStack { Text("HID++ diagnostics").font(.headline); Spacer(); Button(L("common.done")) { model.showDiagnostics = false } }.padding()
                if let mouse = model.selectedMouse { MouseDiagnostics(mouse: mouse) }
            }.frame(width: 650, height: 650)
        }
        .preferredColorScheme(model.appearance)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { model.showDevices.toggle() } label: { ActionGlyph(name: model.showDevices ? "mouse" : "arrow-left", size: 18) }
                .buttonStyle(.plain).help(L("device.devices"))
            Text(model.showDevices ? L("device.devices") : model.selectedMouse?.name ?? "MX Master 4")
                .font(.system(size: 20, weight: .semibold))
            if !model.showDevices, let mouse = model.selectedMouse {
                Text(mouse.connection).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                if let battery = mouse.battery { BatteryIndicator(percentage: Int(battery.percentage)) }
                Text(model.previewEditing ? "Recorded" : L("device.connected")).font(.system(size: 12)).foregroundStyle(.secondary)
            } else { Spacer() }
            if model.busy { ProgressView().controlSize(.small) }
            Button { model.showAgentSettings = true } label: { ActionGlyph(name: "settings", size: 18) }
                .buttonStyle(.plain).help("Application settings")
        }.padding(.horizontal, 20).frame(height: Layout.header)
    }

    private var rail: some View {
        let p = Palette(scheme: scheme)
        return VStack(spacing: 4) {
            ForEach(DeviceSection.allCases) { section in
                Button {
                    model.section = section; model.search = ""; model.actionLibraryOpen = false
                } label: {
                    HStack(spacing: 9) { ActionGlyph(name: section.icon); Text(L(section.key)) }
                }.buttonStyle(ChoiceStyle(selected: model.section == section))
            }
            Spacer()
        }.padding(12).frame(width: Layout.rail).background(p.panel)
    }

    private var profileBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button(L("profiles.all_applications")) { model.profileID = "default" }
                        .buttonStyle(ChoiceStyle(selected: model.profileID == "default"))
                    ForEach(model.profileNames.keys.sorted(), id: \.self) { id in
                        Button(model.profileNames[id] ?? id) { model.profileID = id }
                            .buttonStyle(ChoiceStyle(selected: model.profileID == id))
                    }
                }.fixedSize(horizontal: true, vertical: false)
            }
            Button { model.chooseProfileApplication() } label: {
                HStack(spacing: 4) { ActionGlyph(name: "square-plus", size: 14); Text(L("profiles.add_app")) }
            }.disabled(!model.previewEditing)
            Menu {
                Button(L("profiles.reset_profile")) { model.resetProfile() }
                if model.profileID != "default" { Button(L("profiles.remove_profile")) { model.removeProfile() } }
            } label: { ActionGlyph(name: "settings") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28).disabled(!model.previewEditing).help(L("profiles.profile_options"))
        }.padding(.horizontal, 20).frame(height: 54)
    }

    private var gallery: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)
            Button { if model.selectedMouse != nil { model.showDevices = false } } label: {
                VStack(spacing: 16) {
                    Image(nsImage: DeviceArt.image("front_core.png")).resizable().scaledToFit().frame(height: 240)
                    Text("MX Master 4").font(.system(size: 20, weight: .semibold))
                    Text(model.selectedMouse?.connection ?? L("device.no_devices_connected")).foregroundStyle(.secondary)
                }.padding(32).frame(width: 340)
                    .background(Palette(scheme: scheme).panel, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette(scheme: scheme).border))
            }.buttonStyle(.plain)
            HStack {
                Button("Open hardware recording…") { model.chooseRecording() }
                Button("Connect agent…") { model.showAgentSettings = true }
            }.disabled(model.busy)
            Spacer(minLength: 24)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct BatteryIndicator: View {
    let percentage: Int
    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 1) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).stroke(.secondary, lineWidth: 1)
                    RoundedRectangle(cornerRadius: 1).fill(percentage <= 10 ? Color.red : Color.secondary)
                        .frame(width: CGFloat(max(0, min(100, percentage))) * 0.18, height: 7).padding(2)
                }.frame(width: 22, height: 11)
                Rectangle().fill(.secondary).frame(width: 2, height: 5)
            }
            Text("\(percentage)%").font(.system(size: 12)).monospacedDigit()
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(L("device.battery")): \(percentage)%")
    }
}
