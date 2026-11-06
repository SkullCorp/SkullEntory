import AppIntents
import UIKit
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct BridgeEntry: TimelineEntry {
    let date: Date
    let sourceID: String?
    let sourceName: String
    let payload: WidgetPayload?
    let fetchedAt: Date?
    let error: String?
    let lastAction: ActionResult?

    static let placeholder = BridgeEntry(
        date: Date(), sourceID: nil, sourceName: "Inventaire", payload: .sample,
        fetchedAt: Date(), error: nil, lastAction: nil
    )
}

struct BridgeProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BridgeEntry { .placeholder }

    func snapshot(for configuration: SelectSourceIntent, in context: Context) async -> BridgeEntry {
        if context.isPreview, SharedStore.shared.loadSources().isEmpty { return .placeholder }
        return await makeEntry(for: configuration, network: !context.isPreview)
    }

    func timeline(for configuration: SelectSourceIntent, in context: Context) async -> Timeline<BridgeEntry> {
        let entry = await makeEntry(for: configuration, network: true)
        // En cas d'erreur on retente plus vite ; sinon on respecte "refresh" (min 5 min, iOS reste maître).
        let seconds = entry.error != nil ? 300 : max(300, entry.payload?.refresh ?? 900)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(TimeInterval(seconds))))
    }

    private func makeEntry(for configuration: SelectSourceIntent, network: Bool) async -> BridgeEntry {
        let store = SharedStore.shared
        let sources = store.loadSources()
        let selected = configuration.source.flatMap { entity in sources.first { $0.id.uuidString == entity.id } }

        guard let source = selected ?? sources.first else {
            let message = store.isShared
                ? "Ajoute une web app dans SkullWidgets"
                : "App Group indisponible : réinstalle via SideStore/AltStore"
            return BridgeEntry(date: Date(), sourceID: nil, sourceName: "SkullWidgets", payload: nil,
                               fetchedAt: nil, error: message, lastAction: nil)
        }

        let cached = store.cached(for: source.id)
        var payload = cached?.payload
        var fetchedAt = cached?.date
        var errorText: String?

        if network {
            do {
                let fresh = try await BridgeClient.shared.fetchPayload(for: source)
                store.storeCache(fresh, for: source.id)
                payload = fresh
                fetchedAt = Date()
            } catch {
                errorText = error.localizedDescription
            }
        }

        // N'affiche le retour d'une action que pendant 10 minutes.
        let last = store.lastAction(for: source.id).flatMap { $0.date.timeIntervalSinceNow > -600 ? $0 : nil }

        return BridgeEntry(date: Date(), sourceID: source.id.uuidString, sourceName: source.displayName,
                           payload: payload, fetchedAt: fetchedAt, error: errorText, lastAction: last)
    }
}

// MARK: - Vues

struct BridgeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BridgeEntry

    private var payload: WidgetPayload? { entry.payload }
    private var tint: Color { payload?.tintColor ?? .orange }

    var body: some View {
        content
            .widgetURL(openURL)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemSmall: small
        case .systemMedium: medium
        default: large
        }
    }

    private var openURL: URL? {
        var c = URLComponents()
        c.scheme = "skullwidgets"
        if let target = payload?.url {
            c.host = "open"
            c.queryItems = [URLQueryItem(name: "url", value: target)]
        } else {
            c.host = "source"
            c.queryItems = [URLQueryItem(name: "id", value: entry.sourceID ?? "")]
        }
        return c.url
    }

    // MARK: Écran d'accueil

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            PayloadHeader(payload: payload, fallbackTitle: entry.sourceName, showSubtitle: false, warning: entry.error != nil)
            if let payload {
                if payload.value != nil || payload.gauge != nil {
                    HeroValue(payload: payload)
                    ForEach(Array(payload.items.prefix(payload.actions.isEmpty ? 2 : 1).enumerated()), id: \.offset) { _, item in
                        ItemRow(item: item, compact: true)
                    }
                } else {
                    ForEach(Array(payload.items.prefix(payload.actions.isEmpty ? 4 : 3).enumerated()), id: \.offset) { _, item in
                        ItemRow(item: item, compact: true)
                    }
                }
                Spacer(minLength: 0)
                if let action = payload.actions.first {
                    actionButton(action)
                } else {
                    footer
                }
            } else {
                emptyState
            }
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                PayloadHeader(payload: payload, fallbackTitle: entry.sourceName, warning: entry.error != nil)
                if let payload {
                    HeroValue(payload: payload)
                    let maxItems = (payload.value != nil || payload.gauge != nil) ? 2 : 4
                    ForEach(Array(payload.items.prefix(maxItems).enumerated()), id: \.offset) { _, item in
                        ItemRow(item: item, compact: true)
                    }
                    Spacer(minLength: 0)
                    footer
                } else {
                    emptyState
                }
            }
            if let actions = payload?.actions, !actions.isEmpty {
                VStack(spacing: 6) {
                    ForEach(actions.prefix(3)) { action in
                        actionButton(action)
                    }
                }
                .frame(width: 112)
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            PayloadHeader(payload: payload, fallbackTitle: entry.sourceName, warning: entry.error != nil)
            if let payload {
                HeroValue(payload: payload, large: true)
                if payload.value != nil, payload.gauge != nil, let gauge = payload.gauge {
                    Gauge(value: gauge.clamped, in: gauge.lower...gauge.upper) { EmptyView() }
                        .gaugeStyle(.linearCapacity)
                        .tint(tint)
                }
                Divider()
                ForEach(Array(payload.items.prefix(7).enumerated()), id: \.offset) { _, item in
                    ItemRow(item: item)
                }
                Spacer(minLength: 0)
                if !payload.actions.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(payload.actions.prefix(4)) { action in
                            actionButton(action)
                        }
                    }
                }
                footer
            } else {
                emptyState
            }
        }
    }

    // MARK: Écran verrouillé

    @ViewBuilder
    private var circular: some View {
        if let gauge = payload?.gauge {
            Gauge(value: gauge.clamped, in: gauge.lower...gauge.upper) {
                Image(systemName: payload?.iconName ?? "globe")
            } currentValueLabel: {
                Text(payload?.value ?? LenientFormat.number(gauge.value))
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: payload?.iconName ?? "globe").font(.caption)
                    Text(payload?.value ?? payload?.items.first?.value ?? "–")
                        .font(.headline)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .padding(4)
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(payload?.title ?? entry.sourceName, systemImage: payload?.iconName ?? "globe")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if let value = payload?.value {
                Text([value, payload?.unit].compactMap { $0 }.joined(separator: " "))
                    .font(.headline)
                    .lineLimit(1)
            }
            ForEach(Array((payload?.items ?? []).prefix(payload?.value == nil ? 2 : 1).enumerated()), id: \.offset) { _, item in
                Text("\(item.label) : \(item.value ?? "")").font(.caption2).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        let title = payload?.title ?? entry.sourceName
        let value = payload?.value ?? payload?.items.first?.value
        return Label(value.map { "\(title) : \($0)" } ?? title, systemImage: payload?.iconName ?? "globe")
    }

    // MARK: Éléments

    private func actionButton(_ action: WidgetAction) -> some View {
        Button(intent: RunWidgetActionIntent(sourceID: entry.sourceID ?? "", action: action)) {
            ActionLabel(action: action)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(Color(bridge: action.color) ?? tint)
        .disabled(entry.sourceID == nil)
    }

    @ViewBuilder
    private var footer: some View {
        if let last = entry.lastAction {
            Label(last.label, systemImage: last.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.caption2)
                .foregroundStyle(last.success ? .green : .red)
                .lineLimit(1)
        } else if let error = entry.error {
            Text(error).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        } else if let fetched = entry.fetchedAt {
            Text(fetched, style: .time).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 0)
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(.secondary)
            Text(entry.error ?? "Aucune donnée")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Widget

struct BridgeWidget: Widget {
    let kind = "SkullWidgetsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectSourceIntent.self, provider: BridgeProvider()) { entry in
            BridgeWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [(entry.payload?.tintColor ?? .orange).opacity(0.22), Color(.systemBackground)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Web app")
        .description("Affiche les infos d'une web app et déclenche ses actions.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

@main
struct SkullWidgetsWidgetBundle: WidgetBundle {
    var body: some Widget {
        BridgeWidget()
    }
}
