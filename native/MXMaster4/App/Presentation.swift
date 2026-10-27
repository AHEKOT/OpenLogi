import AppKit
import SwiftUI

/// Generated from the Rust UI's catalogs, defaults, SVGs and theme; see Scripts/import_resources.py.
struct Presentation: Decodable {
    struct Action: Decodable, Identifiable, Equatable {
        let id: String
        let key: String
        let category: String
        let icon: String
    }
    struct Theme: Decodable { let mode: String; let colors: [String: String] }
    struct WheelPreset: Decodable, Identifiable {
        let id: String
        let key: String
        let backward: String
        let forward: String
    }
    struct SliderDomain: Decodable {
        let min: Double
        let max: Double
        let `default`: Double
        var range: ClosedRange<Double> { min...max }
    }
    let sensitivity: SliderDomain
    let smartShiftThreshold: SliderDomain
    let locales: [String: [String: String]]
    let actions: [Action]
    let themes: [Theme]
    let mouseDefaults: [String: String]
    let gestureDefaults: [String: String]
    let ringDefaults: [String]
    let thumbwheelPresets: [WheelPreset]

    static let shared: Presentation = load("presentation.json")
    static func load<T: Decodable>(_ name: String) -> T {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(name),
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(T.self, from: data) else {
            preconditionFailure("Missing or invalid bundled presentation resource: \(name)")
        }
        return value
    }
    func text(_ key: String, locale: String = Locale.preferredLanguages.first ?? "en") -> String {
        let exact = locales[locale] ?? locales[String(locale.split(separator: "-").first ?? "en")]
        return exact?[key] ?? locales["en"]?[key] ?? key
    }
    func action(_ id: String) -> Action? { actions.first { $0.id == id } }
}

func L(_ key: String) -> String { Presentation.shared.text(key) }

struct ActionGlyph: View {
    let name: String
    var size: CGFloat = 16
    var body: some View {
        Image("ol-\(name)").renderingMode(.template).resizable()
            .scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct Palette {
    let scheme: ColorScheme
    private var colors: [String: String] {
        Presentation.shared.themes.first { $0.mode == (scheme == .dark ? "dark" : "light") }!.colors
    }
    func color(_ key: String) -> Color {
        let hex = String((colors[key] ?? "#808080").dropFirst())
        let value = UInt32(hex, radix: 16) ?? 0x808080
        return Color(red: Double(value >> 16 & 255) / 255, green: Double(value >> 8 & 255) / 255, blue: Double(value & 255) / 255)
    }
    var page: Color { color("background") }
    var panel: Color { color("group_box.background") }
    var text: Color { color("foreground") }
    var muted: Color { color("muted.foreground") }
    var border: Color { color("border") }
    var hover: Color { color("secondary.hover.background") }
    var accent: Color { color("ring") }
}

enum Layout {
    static let header: CGFloat = 64
    static let rail: CGFloat = 168
    static let inspector: CGFloat = 328
    static let screenPadding: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let controlRadius: CGFloat = 6
    static let cardRadius: CGFloat = 9
}

struct Panel<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) { ActionGlyph(name: icon); Text(title).font(.system(size: 15, weight: .semibold)) }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(Layout.cardPadding)
        .background(p.panel, in: RoundedRectangle(cornerRadius: Layout.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Layout.cardRadius).stroke(p.border, lineWidth: 1))
    }
}

struct ChoiceStyle: ButtonStyle {
    var selected = false
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        let p = Palette(scheme: scheme)
        configuration.label.padding(.horizontal, 12).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? p.accent.opacity(0.12) : configuration.isPressed ? p.hover : .clear,
                        in: RoundedRectangle(cornerRadius: Layout.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Layout.controlRadius).stroke(selected ? p.accent : .clear, lineWidth: 1))
            .contentShape(Rectangle())
    }
}
