import SwiftUI

/// Right-aligned line chart over a fixed window: the newest value sits at the right edge.
struct Sparkline: View {
    let values: [Double]
    var maxValue: Double? = nil
    var capacity: Int = 120
    var color: Color = Tokens.ink

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let top = max(maxValue ?? (values.max() ?? 1), 0.0001)
            let step = size.width / CGFloat(max(capacity - 1, 1))
            let offset = CGFloat(max(capacity - values.count, 0)) * step
            var path = Path()
            for (index, value) in values.suffix(capacity).enumerated() {
                let ratio = CGFloat(min(max(value / top, 0), 1))
                let point = CGPoint(x: offset + CGFloat(index) * step, y: size.height - 1 - ratio * (size.height - 2))
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
        }
    }
}

/// Small bar strip; the newest bar is darker (Vesper microbars).
struct MicroBars: View {
    let values: [Double]
    var count = 24

    var body: some View {
        Canvas { context, size in
            let recent = Array(values.suffix(count))
            guard !recent.isEmpty else { return }
            let top = max(recent.max() ?? 0, 0.0001)
            let gap: CGFloat = 1.5
            let width = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)
            let start = count - recent.count
            for (index, value) in recent.enumerated() {
                let height = max(2, CGFloat(value / top) * size.height)
                let rect = CGRect(x: CGFloat(start + index) * (width + gap), y: size.height - height, width: width, height: height)
                let opacity = index == recent.count - 1 ? 0.72 : 0.17
                context.fill(Path(rect), with: .color(Tokens.ink.opacity(opacity)))
            }
        }
        .frame(width: 96, height: 23)
    }
}

/// 3 pt progress track; vermilion only when the value is a risk.
struct Meter: View {
    let fraction: Double
    var signal = false
    var width: CGFloat = 150

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Tokens.track)
            RoundedRectangle(cornerRadius: 2)
                .fill(signal ? Tokens.signal : Tokens.ink.opacity(0.8))
                .frame(width: width * CGFloat(min(max(fraction, 0), 1)))
        }
        .frame(width: width, height: 3)
    }
}

/// One cell per logical core, ink density = utilisation. Never vermilion: a busy core is not a risk.
struct CoreHeatmap: View {
    let perCore: [Double]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(perCore.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Tokens.ink.opacity(0.08 + 0.8 * min(max(perCore[index], 0), 100) / 100))
                    .frame(width: 9, height: 14)
            }
        }
    }
}
