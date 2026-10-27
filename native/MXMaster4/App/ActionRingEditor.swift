import SwiftUI

struct ActionRingEditor: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    private let icons = ["star", "heart", "bell", "calendar", "book-open", "file", "folder", "globe", "palette", "terminal"]
    var body: some View {
        let p = Palette(scheme: scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("action_ring.actions_ring")).font(.system(size: 20, weight: .semibold))
                    Text(L("action_ring.action_ring_description")).foregroundStyle(p.muted)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) { preview.frame(width: 320); library.frame(width: 300) }
                    VStack(spacing: 20) { preview; library }
                }
                Divider()
                Toggle(L("action_ring.show_actions_ring"), isOn: Binding(get: { model.draft.ringEnabled }, set: { value in model.editDraft { $0.ringEnabled = value } }))
                    .toggleStyle(.switch)
                Text(L("action_ring.open_at_the_current_cursor_position")).font(.system(size: 12)).foregroundStyle(p.muted)
                Toggle(L("action_ring.haptic_feedback"), isOn: Binding(get: { model.draft.haptics }, set: { value in model.editDraft { $0.haptics = value } }))
                    .toggleStyle(.switch)
                Text(L("action_ring.action_ring_haptic_description")).font(.system(size: 12)).foregroundStyle(p.muted)
            }.disabled(!model.previewEditing).padding(20).frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
        }
    }

    private var preview: some View {
        let p = Palette(scheme: scheme)
        return VStack(spacing: 14) {
            ZStack {
                Circle().fill(p.panel).frame(width: 272, height: 272)
                    .overlay(Circle().stroke(p.border, lineWidth: 1))
                ForEach(0..<8) { slot in
                    let angle = Double(slot) * .pi / 4 - .pi / 2
                    let action = model.draft.ring[slot]
                    Button { model.selectedRingSlot = slot } label: {
                        ActionGlyph(name: action?.icon ?? "square-plus", size: 22).frame(width: 50, height: 50)
                            .background(slot == model.selectedRingSlot ? p.accent.opacity(0.14) : p.page, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(slot == model.selectedRingSlot ? p.accent : p.border, lineWidth: 1))
                    }.buttonStyle(.plain).position(x: 160 + cos(angle) * 106, y: 160 + sin(angle) * 106)
                        .help(action?.label ?? L("action_ring.empty_slot"))
                        .accessibilityLabel("Slot \(slot + 1): \(action?.label ?? L("action_ring.empty_slot"))")
                }
                ActionGlyph(name: "x", size: 22).foregroundStyle(p.muted).frame(width: 48, height: 48)
                    .background(p.page, in: Circle())
            }.frame(width: 320, height: 320)
            Text(model.draft.ring[model.selectedRingSlot]?.label ?? L("action_ring.empty_slot"))
                .font(.system(size: 15, weight: .medium)).lineLimit(2)
            HStack {
                Menu(L("action_ring.icon")) {
                    Button(L("common.default")) { model.editDraft { $0.ring[model.selectedRingSlot]?.iconOverride = nil } }
                    ForEach(icons, id: \.self) { icon in
                        Button { model.editDraft { $0.ring[model.selectedRingSlot]?.iconOverride = icon } } label: {
                            Label(icon, image: "ol-\(icon)")
                        }
                    }
                }.frame(width: 140).disabled(model.draft.ring[model.selectedRingSlot] == nil)
                Button(L("action_ring.clear_slot")) { model.editDraft { $0.ring[model.selectedRingSlot] = nil } }
            }
        }
    }
    private var library: some View {
        ScrollView { ActionLibrary(model: model, ring: true).padding(12) }
            .frame(minWidth: 260, maxWidth: .infinity).frame(height: 420)
            .background(Palette(scheme: scheme).panel, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette(scheme: scheme).border, lineWidth: 1))
    }
}
