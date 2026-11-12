import SwiftUI
import Charts

/// Line chart of numeric values in a topic's history.
struct TopicChartView: View {
    let messages: [ReceivedMessage]
    @State private var selectedKey: String?

    var body: some View {
        let keys = NumericSeries.keys(in: messages)
        if keys.isEmpty {
            ContentUnavailableView("Keine Zahlenwerte",
                                   systemImage: "chart.xyaxis.line",
                                   description: Text("Diagramme gibt es für Payloads, die eine Zahl oder JSON mit Zahlenwerten enthalten."))
        } else {
            let key = selectedKey.flatMap { keys.contains($0) ? $0 : nil } ?? keys[0]
            let points = NumericSeries.points(for: key, in: messages)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if keys.count > 1 {
                        Picker("Wert", selection: Binding(get: { key }, set: { selectedKey = $0 })) {
                            ForEach(keys, id: \.self) { Text($0).tag($0) }
                        }
                        .fixedSize()
                    }
                    Spacer()
                    if let minimum = points.map(\.value).min(), let maximum = points.map(\.value).max() {
                        Text("\(points.count) Werte · min \(minimum.formatted()) · max \(maximum.formatted()) · zuletzt \(points.last!.value.formatted())")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Chart(points) { point in
                    LineMark(x: .value("Zeit", point.date), y: .value(key, point.value))
                        .interpolationMethod(.monotone)
                    if points.count <= 60 {
                        PointMark(x: .value("Zeit", point.date), y: .value(key, point.value))
                            .symbolSize(20)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute().second())
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .padding(12)
        }
    }
}
