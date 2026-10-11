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

struct CareWidgetView: View {
    var entry: CareEntry
    @Environment(\.widgetFamily) private var family
    private var child: Entity? {
        entry.state.resolvedChild
    }

    var body: some View {
        if family == .accessoryCircular {
            Link(destination: DeepLink.log("diaper").url) {
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
            .widgetURL(DeepLink.log("feeding").url)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(child?.title ?? "Add a child").font(.headline); Spacer(); Image(systemName: "moon.stars.fill")
                        .foregroundStyle(CarePalette.tint("indigo"))
                }
                let feed = entry.state.visibleEntities.filter { $0.type == "feeding" && $0.childID == child?.id }
                    .max { $0.at < $1.at }
                if let feed {
                    HStack { Image(systemName: "waterbottle.fill").foregroundStyle(CarePalette.tint("amber")); Text("Last bottle"); Spacer(); Text(
                        feed.date,
                        style: .relative
                    ).font(.caption).monospacedDigit() }.font(.caption)
                }
                let diaper = entry.state.visibleEntities.filter { $0.type == "diaper" && $0.childID == child?.id }
                    .max { $0.at < $1.at }
                if let diaper {
                    HStack { Image(systemName: "drop.fill").foregroundStyle(CarePalette.tint("mint")); Text("Last diaper"); Spacer(); Text(
                        diaper.date,
                        style: .relative
                    ).font(.caption).monospacedDigit() }.font(.caption)
                }
                Spacer(minLength: 0)
                HStack {
                    Link(destination: DeepLink.log("feeding").url) {
                        Label("Bottle", systemImage: "plus").font(.caption.weight(.semibold)).foregroundStyle(CarePalette.tint("amber"))
                    }
                    Spacer()
                    Button(intent: WetDiaperIntent()) {
                        Label("Wet", systemImage: "drop.fill").font(.caption.weight(.semibold))
                    }.buttonStyle(.plain).foregroundStyle(CarePalette.tint("mint"))
                }
            }
        }
    }
}

struct CareWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BabyCare", provider: CareProvider()) { entry in
            CareWidgetView(entry: entry).containerBackground(
                CarePalette.paper,
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
                Image(systemName: "moon.zzz.fill").font(.title).foregroundStyle(CarePalette.tint("indigo"))
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
                Link(destination: DeepLink.endSleep(context.attributes.sessionID).url) {
                    Image(systemName: "stop.fill").padding(12).background(
                        CarePalette.tint("indigo").opacity(0.12),
                        in: Circle()
                    )
                }.accessibilityLabel("End sleep")
            }.padding(18).activityBackgroundTint(CarePalette.paper)
                .widgetURL(DeepLink.openSleep(context.attributes.sessionID).url)
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
                    destination: DeepLink.endSleep(context.attributes.sessionID).url
                ).font(.headline) }
            } compactLeading: { Image(systemName: "moon.zzz.fill") } compactTrailing: { Text(
                Date(timeIntervalSince1970: context.state.startedAt),
                style: .timer
            ).monospacedDigit().frame(width: 52) } minimal: { Image(systemName: "moon.zzz.fill") }
                .widgetURL(DeepLink.openSleep(context.attributes.sessionID).url)
        }
    }
}

@main struct BabyWidgetBundle: WidgetBundle {
    var body: some Widget {
        CareWidget(); SleepWidget()
    }
}
