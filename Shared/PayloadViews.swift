import SwiftUI

// MARK: - Couleurs depuis le JSON

extension Color {
    /// "#RGB", "#RRGGBB", "#RRGGBBAA" ou un nom simple (red, green, orange…).
    init?(bridge string: String?) {
        guard var s = string?.trimmingCharacters(in: .whitespaces).lowercased(), !s.isEmpty else { return nil }
        let named: [String: Color] = [
            "red": .red, "orange": .orange, "yellow": .yellow, "green": .green, "mint": .mint,
            "teal": .teal, "cyan": .cyan, "blue": .blue, "indigo": .indigo, "purple": .purple,
            "pink": .pink, "brown": .brown, "gray": .gray, "grey": .gray, "white": .white,
            "black": .black, "primary": .primary, "secondary": .secondary,
        ]
        if let c = named[s] { self = c; return }
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let hasAlpha = s.count == 8
        let r = Double((v >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = Double((v >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = Double((v >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? Double(v & 0xFF) / 255 : 1
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

extension WidgetPayload {
    var tintColor: Color { Color(bridge: tint) ?? .orange }
    var iconName: String { icon ?? "globe" }
}

// MARK: - Briques réutilisées par le widget et l'app

struct PayloadHeader: View {
    let payload: WidgetPayload?
    let fallbackTitle: String
    var showSubtitle = true
    var warning = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: payload?.iconName ?? "globe")
                .font(.caption.weight(.bold))
                .foregroundStyle(payload?.tintColor ?? .orange)
            VStack(alignment: .leading, spacing: 0) {
                Text(payload?.title ?? fallbackTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if showSubtitle, let sub = payload?.subtitle {
                    Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
    }
}

struct HeroValue: View {
    let payload: WidgetPayload
    var large = false

    var body: some View {
        if let value = payload.value {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: large ? 44 : 34, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                if let unit = payload.unit {
                    Text(unit).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        } else if let gauge = payload.gauge {
            VStack(alignment: .leading, spacing: 2) {
                if let label = gauge.label {
                    Text(label).font(.caption2).foregroundStyle(.secondary)
                }
                Gauge(value: gauge.clamped, in: gauge.lower...gauge.upper) { EmptyView() }
                    .gaugeStyle(.linearCapacity)
                    .tint(payload.tintColor)
            }
        }
    }
}

struct ItemRow: View {
    let item: WidgetItem
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            if let icon = item.icon {
                Image(systemName: icon)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(Color(bridge: item.color) ?? .secondary)
                    .frame(width: compact ? 14 : 18)
            }
            Text(item.label)
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let value = item.value {
                Text(value)
                    .font((compact ? Font.caption : Font.subheadline).weight(.semibold))
                    .foregroundStyle(Color(bridge: item.color) ?? .primary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
        }
    }
}

struct ActionLabel: View {
    let action: WidgetAction
    var iconOnly = false

    var body: some View {
        if iconOnly {
            Image(systemName: action.icon ?? "bolt.fill")
        } else {
            Label(action.label, systemImage: action.icon ?? "bolt.fill")
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
