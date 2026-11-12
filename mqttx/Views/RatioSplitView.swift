import SwiftUI

/// Split view whose divider position is stored as a ratio (first pane / total size)
/// in UserDefaults, so the proportions survive window resizes and app restarts.
/// `.horizontal` places the panes side by side, `.vertical` stacks them.
struct RatioSplitView<First: View, Second: View>: View {
    @AppStorage private var ratio: Double
    let axis: Axis
    let defaultRatio: Double
    let minFirst: CGFloat
    let minSecond: CGFloat
    let first: First
    let second: Second

    @State private var dragStartRatio: Double?

    init(autosaveName: String,
         axis: Axis = .horizontal,
         defaultRatio: Double = 0.4,
         minFirst: CGFloat = 200,
         minSecond: CGFloat = 300,
         @ViewBuilder first: () -> First,
         @ViewBuilder second: () -> Second) {
        _ratio = AppStorage(wrappedValue: defaultRatio, "splitRatio." + autosaveName)
        self.axis = axis
        self.defaultRatio = defaultRatio
        self.minFirst = minFirst
        self.minSecond = minSecond
        self.first = first()
        self.second = second()
    }

    var body: some View {
        GeometryReader { proxy in
            let total = axis == .horizontal ? proxy.size.width : proxy.size.height
            let firstSize = clampedFirstSize(ratio * total, total: total)
            if axis == .horizontal {
                HStack(spacing: 0) {
                    first.frame(width: firstSize)
                    divider(total: total)
                    second.frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    first.frame(height: firstSize)
                    divider(total: total)
                    second.frame(maxHeight: .infinity)
                }
            }
        }
    }

    private func divider(total: CGFloat) -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: axis == .horizontal ? 1 : nil, height: axis == .vertical ? 1 : nil)
            .frame(maxWidth: axis == .vertical ? .infinity : nil, maxHeight: axis == .horizontal ? .infinity : nil)
            // Wider invisible hit area for easier grabbing.
            .overlay {
                Color.clear
                    .frame(width: axis == .horizontal ? 8 : nil, height: axis == .vertical ? 8 : nil)
                    .contentShape(Rectangle())
                    .pointerStyle(axis == .horizontal ? .columnResize : .rowResize)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = dragStartRatio ?? ratio
                                if dragStartRatio == nil { dragStartRatio = start }
                                guard total > 0 else { return }
                                let delta = axis == .horizontal ? value.translation.width : value.translation.height
                                ratio = clampedFirstSize(start * total + delta, total: total) / total
                            }
                            .onEnded { _ in dragStartRatio = nil }
                    )
                    .onTapGesture(count: 2) { ratio = defaultRatio }
            }
    }

    /// Keeps both panes at their minimum size; if there is not enough room,
    /// the first pane wins.
    private func clampedFirstSize(_ size: CGFloat, total: CGFloat) -> CGFloat {
        let upper = max(minFirst, total - minSecond - 1)
        return min(max(size, minFirst), upper)
    }
}

extension RatioSplitView {
    /// Convenience for the horizontal topic browser layout.
    init(autosaveName: String,
         defaultRatio: Double = 0.4,
         minLeft: CGFloat,
         minRight: CGFloat,
         @ViewBuilder left: () -> First,
         @ViewBuilder right: () -> Second) {
        self.init(autosaveName: autosaveName, axis: .horizontal, defaultRatio: defaultRatio,
                  minFirst: minLeft, minSecond: minRight, first: left, second: right)
    }
}
