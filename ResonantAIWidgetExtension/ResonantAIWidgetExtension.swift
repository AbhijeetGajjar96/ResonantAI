//
//  ResonantAIWidgetExtension.swift
//  ResonantAIWidgetExtension
//
//  Created by Abhijeet gajjar on 7/1/25.
//

import WidgetKit
import SwiftUI
import ActivityKit

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), emoji: "😀")
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), emoji: "😀")
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        var entries: [SimpleEntry] = []

        // Generate a timeline consisting of five entries an hour apart, starting from the current date.
        let currentDate = Date()
        for hourOffset in 0 ..< 5 {
            let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate)!
            let entry = SimpleEntry(date: entryDate, emoji: "😀")
            entries.append(entry)
        }

        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }

//    func relevances() async -> WidgetRelevances<Void> {
//        // Generate a list containing the contexts this widget is relevant in.
//    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let emoji: String
}

struct ResonantAIWidgetExtensionEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        VStack(spacing: 8) {
            Text("ResonantAI")
                .font(.headline)
                .foregroundColor(.blue)
            Text("Session")
                .font(.subheadline)
                .foregroundColor(.primary)
            Text(entry.date, style: .time)
                .font(.caption)
                .foregroundColor(.secondary)
            // Simple waveform bar (static, for demo)
            HStack(spacing: 2) {
                ForEach(0..<12, id: \ .self) { i in
                    Capsule()
                        .fill(Color.blue)
                        .frame(width: 3, height: CGFloat((i % 3 + 1) * 10))
                }
            }
            .frame(height: 24)
            Text(entry.emoji)
                .font(.largeTitle)
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

struct ResonantAIWidgetExtension: Widget {
    let kind: String = "ResonantAIWidgetExtension"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                ResonantAIWidgetExtensionEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                ResonantAIWidgetExtensionEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("My Widget")
        .description("This is an example widget.")
    }
}

#Preview(as: .systemSmall) {
    ResonantAIWidgetExtension()
} timeline: {
    SimpleEntry(date: .now, emoji: "😀")
    SimpleEntry(date: .now, emoji: "🤩")
}

struct RecordingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: String
        var progress: Double
    }
    var sessionTitle: String
}

struct RecordingLiveActivityWidget: Widget {
    let kind: String = "RecordingLiveActivityWidget"
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            VStack(spacing: 8) {
                Text(context.attributes.sessionTitle)
                    .font(.headline)
                    .foregroundColor(.blue)
                Text(context.state.status)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                ProgressView(value: context.state.progress)
                    .accentColor(.blue)
                    .frame(height: 8)
            }
            .padding()
            .background(Color(.systemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.status)
                        .font(.subheadline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ProgressView(value: context.state.progress)
                        .accentColor(.blue)
                        .frame(height: 8)
                }
            } compactLeading: {
                Image(systemName: "mic.fill")
                    .foregroundColor(.blue)
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))%")
                    .foregroundColor(.blue)
            } minimal: {
                Image(systemName: "mic.fill")
                    .foregroundColor(.blue)
            }
        }
    }
}
