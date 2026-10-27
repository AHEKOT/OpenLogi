import AppKit
import SwiftUI

struct DeviceMetadata: Decodable {
    struct ImageSpec: Decodable {
        struct Origin: Decodable { let width: CGFloat; let height: CGFloat }
        struct Marker: Decodable { let x: CGFloat; let y: CGFloat }
        struct Assignment: Decodable { let slotName: String; let marker: Marker }
        let key: String
        let origin: Origin
        let assignments: [Assignment]?
    }
    let images: [ImageSpec]
    static let shared: Self = Presentation.load("Device/core_metadata.json")
    var buttons: ImageSpec { images.first { $0.key == "device_buttons_image" }! }
}

@MainActor enum DeviceArt {
    private static var cache: [String: NSImage] = [:]
    static func image(_ name: String) -> NSImage {
        if let value = cache[name] { return value }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Device/\(name)"),
              let value = NSImage(contentsOf: url) else { preconditionFailure("Missing device art: \(name)") }
        cache[name] = value
        return value
    }
}

/// Port of features/mouse/geometry.rs. Coordinates use the silhouette bbox inside the PNG.
struct DiagramLayout {
    struct Marker: Identifiable { let id: MouseControl; let point: CGPoint; var label: CGPoint?; var left = true }
    let image: CGRect
    let markers: [Marker]
    init(size: CGSize, pngSize: CGSize, labels: Bool) {
        let metadata = DeviceMetadata.shared.buttons
        let bothSides = labels && size.width >= 700
        let gutter: CGFloat = labels ? 180 : 0
        let maxWidth = max(40, size.width - gutter * (bothSides ? 2 : 1) - 24)
        let scale = min(max(80, size.height - 32) / pngSize.height, maxWidth / pngSize.width)
        let width = pngSize.width * scale, height = pngSize.height * scale
        let canvasWidth = width + gutter * (bothSides ? 2 : 1)
        let origin = CGPoint(x: (size.width - canvasWidth) / 2 + gutter, y: (size.height - height) / 2)
        image = CGRect(origin: origin, size: CGSize(width: width, height: height))
        let bbox = width * min(metadata.origin.width, pngSize.width) / pngSize.width
        var values = (metadata.assignments ?? []).compactMap { a -> Marker? in
            guard let id = MouseControl.slot(a.slotName) else { return nil }
            return Marker(id: id, point: CGPoint(x: origin.x + (width - bbox) / 2 + a.marker.x / 100 * bbox,
                                                 y: origin.y + a.marker.y / 100 * height))
        }
        if bothSides {
            let sorted = values.indices.sorted { values[$0].point.x < values[$1].point.x }
            for i in sorted.dropFirst((values.count + 1) / 2) { values[i].left = false }
        }
        if labels {
            for left in [true, false] {
                var order = values.indices.filter { values[$0].left == left }.sorted { values[$0].point.y < values[$1].point.y }
                var pair: (Int, Int)?
                if let back = order.firstIndex(where: { values[$0].id == .back }),
                   let forward = order.firstIndex(where: { values[$0].id == .forward }) {
                    let first = min(back, forward), second = max(back, forward)
                    if second > first + 1 { let moved = order.remove(at: second); order.insert(moved, at: first + 1) }
                    pair = (order[first], order[first + 1])
                }
                // Keep label cards separate when the narrow canvas shrinks the photograph.
                let labelHeight = max(height, CGFloat(order.count + 1) * 56)
                let labelTop = (size.height - labelHeight) / 2
                let step = labelHeight / CGFloat(order.count + 1)
                for (slot, i) in order.enumerated() {
                    values[i].label = CGPoint(x: left ? origin.x - 102 : image.maxX + 102,
                                              y: labelTop + step * CGFloat(slot + 1))
                }
                if let (first, second) = pair {
                    let adjustment = (step - min(step, 72)) / 2
                    values[first].label?.y += adjustment
                    values[second].label?.y -= adjustment
                }
            }
        }
        markers = values
    }
}

struct MouseDiagram: View {
    @ObservedObject var model: AppModel
    let showLabels: Bool
    @Environment(\.colorScheme) private var scheme
    @State private var hovered: MouseControl?
    var body: some View {
        let p = Palette(scheme: scheme)
        GeometryReader { proxy in
            let art = DeviceArt.image("side_core.png")
            let layout = DiagramLayout(size: proxy.size, pngSize: art.size, labels: showLabels)
            ZStack(alignment: .topLeading) {
                Image(nsImage: art).resizable().scaledToFit()
                    .frame(width: layout.image.width, height: layout.image.height)
                    .position(x: layout.image.midX, y: layout.image.midY).accessibilityHidden(true)
                Canvas { context, _ in
                    for marker in layout.markers {
                        guard let label = marker.label else { continue }
                        var line = Path()
                        line.move(to: marker.point)
                        line.addLine(to: CGPoint(x: marker.point.x + (marker.left ? -10 : 10), y: marker.point.y))
                        line.addLine(to: CGPoint(x: label.x + (marker.left ? 78 : -78), y: label.y))
                        let active = model.selectedControl == marker.id || hovered == marker.id
                        context.stroke(line, with: .color(active ? p.accent : p.muted.opacity(0.55)), lineWidth: active ? 1.5 : 1)
                    }
                }.allowsHitTesting(false)
                ForEach(layout.markers) { marker in
                    let active = model.selectedControl == marker.id || hovered == marker.id
                    Button { model.select(marker.id) } label: {
                        Circle().fill(active ? p.accent : Color.white).frame(width: 12, height: 12)
                            .overlay(Circle().stroke(active ? Color.white : p.muted, lineWidth: 2))
                            .shadow(color: .black.opacity(0.25), radius: 2)
                            .frame(width: 56, height: 56).contentShape(Circle())
                    }.buttonStyle(.plain).position(marker.point)
                        .accessibilityLabel(L(marker.id.key)).help(L(marker.id.key))
                        .onHover { hovered = $0 ? marker.id : nil }
                    if let label = marker.label {
                        Button { model.select(marker.id) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(L(marker.id.key)).font(.system(size: 11)).foregroundStyle(p.muted)
                                HStack(spacing: 6) {
                                    let action = model.assignment(for: marker.id)
                                    ActionGlyph(name: action?.icon ?? "ban", size: 14)
                                    Text(model.previewEditing ? action?.label ?? L("actions.unbound") : L("common.unavailable"))
                                        .font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Spacer(minLength: 0)
                                    ActionGlyph(name: "chevron-right", size: 12)
                                }
                            }.padding(.horizontal, 10).frame(width: 156, height: 56, alignment: .leading)
                                .background(active ? p.accent.opacity(0.10) : p.panel, in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(active ? p.accent : p.border, lineWidth: 1))
                        }.buttonStyle(.plain).position(label).help(L(marker.id.key))
                            .onHover { hovered = $0 ? marker.id : nil }
                    }
                }
            }
        }
    }
}
