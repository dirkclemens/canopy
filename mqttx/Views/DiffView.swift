import SwiftUI

/// Unified line diff between two messages, rendered in the chosen payload format.
struct DiffView: View {
    let old: ReceivedMessage
    let new: ReceivedMessage
    let format: PayloadFormat

    var body: some View {
        let lines = TextDiff.diff(old: render(old), new: render(new))
        let added = lines.filter { $0.kind == .added }.count
        let removed = lines.filter { $0.kind == .removed }.count
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Label(old.receivedAt.formatted(date: .omitted, time: .standard), systemImage: "minus.square")
                    .foregroundStyle(.red)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Label(new.receivedAt.formatted(date: .omitted, time: .standard), systemImage: "plus.square")
                    .foregroundStyle(.green)
                Spacer()
                Text(added == 0 && removed == 0 ? "identisch" : "+\(added) / −\(removed) Zeilen")
                    .foregroundStyle(.secondary)
            }
            .font(.callout.monospacedDigit())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { line in
                        row(line)
                    }
                }
                .padding(.vertical, 6)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(maxHeight: .infinity)
    }

    private func render(_ message: ReceivedMessage) -> String {
        let resolved = format == .auto ? PayloadFormatter.autoFormat(for: message.payload) : format
        return PayloadFormatter.render(message.payload, as: resolved)
    }

    private func row(_ line: TextDiff.Line) -> some View {
        HStack(spacing: 0) {
            Text(line.oldNumber.map(String.init) ?? "")
                .frame(width: 36, alignment: .trailing)
                .foregroundStyle(.tertiary)
            Text(line.newNumber.map(String.init) ?? "")
                .frame(width: 36, alignment: .trailing)
                .foregroundStyle(.tertiary)
            Text(symbol(line.kind))
                .frame(width: 20)
                .foregroundStyle(color(line.kind))
            Text(line.text.isEmpty ? " " : line.text)
                .fixedSize()
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.system(.body, design: .monospaced))
        .padding(.trailing, 12)
        .background(color(line.kind).opacity(line.kind == .unchanged ? 0 : 0.15))
    }

    private func symbol(_ kind: TextDiff.Kind) -> String {
        switch kind {
        case .unchanged: " "
        case .added: "+"
        case .removed: "−"
        }
    }

    private func color(_ kind: TextDiff.Kind) -> Color {
        switch kind {
        case .unchanged: .primary
        case .added: .green
        case .removed: .red
        }
    }
}
