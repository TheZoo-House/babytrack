import ActivityKit
import AppIntents
import BabyCore
import SwiftUI
import WidgetKit

struct CareEntry: TimelineEntry {
    var date: Date
    var state: DiskState
}

struct CareProvider: TimelineProvider {
    func placeholder(in _: Context) -> CareEntry {
        CareEntry(date: .now, state: DiskState())
    }

    func getSnapshot(in _: Context, completion: @escaping (CareEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<CareEntry>) -> Void) {
        completion(Timeline(
            entries: [entry()],
            policy: .after(.now.addingTimeInterval(900))
        ))
    }

    private func entry() -> CareEntry {
        CareEntry(
            date: .now,
            state: (try? SharedStorage.application.read()) ?? DiskState()
        )
    }
}

struct WetDiaperIntent: AppIntent {
    static let title: LocalizedStringResource = "Log wet diaper"
    static let description = IntentDescription("Add a wet diaper to the selected child's journal.")
    func perform() async throws -> some IntentResult {
        let storage = SharedStorage.application
        let state = try storage.read()
        guard let child = state.visibleEntities
            .first(where: { $0.id == state.selectedChildID && $0.type == "child" }) ?? state.visibleEntities
            .first(where: { $0.type == "child" }) else { throw IntentError.noChild }
        try storage.enqueue(Command(entity: Entity(
            type: "diaper",
            childID: child.id,
            title: "Diaper",
            fields: ["contents": "Wet"]
        )))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }

    enum IntentError: Error,
        LocalizedError
    { case noChild; var errorDescription: String? {
        "Open the app and add a child first."
    } }
}

struct CareWidgetView: View {
    var entry: CareEntry
    @Environment(\.widgetFamily) private var family
    private var child: Entity? {
        entry.state.visibleEntities.first { $0.id == entry.state.selectedChildID && $0.type == "child" } ?? entry.state
            .visibleEntities.first { $0.type == "child" }
    }

    var body: some View {
        if family == .accessoryCircular {
            Link(destination: URL(string: "babytrack://diaper")!) {
                VStack { Image(systemName: "drop.fill"); Text("Diaper").font(.caption2) }
            }
        } else if family == .accessoryRectangular {
            VStack(alignment: .leading) {
                Text(child?.title ?? "Babytrack").font(.headline); let sleep = entry.state.visibleEntities
                    .first { $0.type == "sleep" && $0.childID == child?.id && $0.end == nil }; if let sleep
                {
                    HStack { Image(systemName: "moon.zzz.fill"); Text(
                        sleep.date,
                        style: .timer
                    ).monospacedDigit() }
                } else {
                    Text("Bottle & diaper").font(.caption)
                }
            }
            .widgetURL(URL(string: "babytrack://feeding"))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(child?.title ?? "Add a child").font(.headline); Spacer(); Image(systemName: "leaf.fill")
                        .foregroundStyle(.green)
                }
                let feed = entry.state.visibleEntities.filter { $0.type == "feeding" && $0.childID == child?.id }
                    .max { $0.at < $1.at }
                if let feed {
                    HStack { Image(systemName: "waterbottle.fill"); Text("Last bottle"); Spacer(); Text(
                        feed.date,
                        style: .relative
                    ).font(.caption).monospacedDigit() }.font(.caption)
                }
                let diaper = entry.state.visibleEntities.filter { $0.type == "diaper" && $0.childID == child?.id }
                    .max { $0.at < $1.at }
                if let diaper {
                    HStack { Image(systemName: "drop.fill"); Text("Last diaper"); Spacer(); Text(
                        diaper.date,
                        style: .relative
                    ).font(.caption).monospacedDigit() }.font(.caption)
                }
                Spacer(minLength: 0)
                HStack {
                    Link(destination: URL(string: "babytrack://feeding")!) {
                        Label("Bottle", systemImage: "plus").font(.caption.weight(.semibold))
                    }
                    Spacer()
                    Button(intent: WetDiaperIntent()) {
                        Label("Wet", systemImage: "drop.fill").font(.caption.weight(.semibold))
                    }.buttonStyle(.plain)
                }.foregroundStyle(.green)
            }
        }
    }
}

struct CareWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BabyCare", provider: CareProvider()) { entry in
            CareWidgetView(entry: entry).containerBackground(
                .background,
                for: .widget
            )
        }
        .configurationDisplayName("Baby care").description("Recent bottles and diapers, with quick logging.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct SleepWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SleepAttributes.self) { context in
            HStack(spacing: 16) {
                Image(systemName: "moon.zzz.fill").font(.title).foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 5) {
                    Text(context.attributes.childName).font(.headline); Text(context.state.ended ? "Awake" : "Sleeping")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if !context.state.ended {
                    Text(
                        timerInterval: Date(timeIntervalSince1970: context.state.startedAt) ... Date.distantFuture,
                        countsDown: false
                    ).font(.title2.monospacedDigit()).frame(maxWidth: 150)
                }
                Link(destination: URL(string: "babytrack://sleep?session=\(context.attributes.sessionID)")!) {
                    Image(systemName: "stop.fill").padding(12).background(
                        .indigo.opacity(0.12),
                        in: Circle()
                    )
                }.accessibilityLabel("End sleep")
            }.padding(18).activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
                .widgetURL(URL(string: "babytrack://sleep?session=\(context.attributes.sessionID)"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.childName, systemImage: "moon.zzz.fill")
                }
                DynamicIslandExpandedRegion(.trailing) { Text(
                    Date(timeIntervalSince1970: context.state.startedAt),
                    style: .timer
                ).monospacedDigit().frame(maxWidth: 110) }
                DynamicIslandExpandedRegion(.bottom) { Link(
                    "End sleep",
                    destination: URL(string: "babytrack://sleep?session=\(context.attributes.sessionID)")!
                ).font(.headline) }
            } compactLeading: { Image(systemName: "moon.zzz.fill") } compactTrailing: { Text(
                Date(timeIntervalSince1970: context.state.startedAt),
                style: .timer
            ).monospacedDigit().frame(width: 52) } minimal: { Image(systemName: "moon.zzz.fill") }
                .widgetURL(URL(string: "babytrack://sleep?session=\(context.attributes.sessionID)"))
        }
    }
}

@main struct BabyWidgetBundle: WidgetBundle {
    var body: some Widget {
        CareWidget(); SleepWidget()
    }
}
