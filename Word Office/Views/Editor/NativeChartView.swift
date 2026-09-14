import SwiftUI
import Charts

/// Chart type options surfaced in the native insert-chart sheet.
enum NativeChartType: String, CaseIterable {
    case column  = "column"
    case bar     = "bar"
    case line    = "line"
    case pie     = "pie"
    case area    = "area"
    case scatter = "scatter"

    var label: String {
        switch self {
        case .column:  return "Column"
        case .bar:     return "Bar"
        case .line:    return "Line"
        case .pie:     return "Pie"
        case .area:    return "Area"
        case .scatter: return "Scatter"
        }
    }
}

// MARK: - Sample data

private struct ChartSample: Identifiable {
    let id   = UUID()
    let x: String
    let y: Double
    let series: Int
}

private let _barData: [ChartSample] = [
    .init(x: "A", y: 3, series: 1), .init(x: "B", y: 5, series: 1), .init(x: "C", y: 2, series: 1),
    .init(x: "A", y: 4, series: 2), .init(x: "B", y: 3, series: 2), .init(x: "C", y: 5, series: 2),
]
private let _lineData: [ChartSample] = [
    .init(x: "1", y: 1, series: 1), .init(x: "2", y: 3, series: 1),
    .init(x: "3", y: 2, series: 1), .init(x: "4", y: 5, series: 1),
    .init(x: "1", y: 3, series: 2), .init(x: "2", y: 1, series: 2),
    .init(x: "3", y: 4, series: 2), .init(x: "4", y: 2, series: 2),
]
private let _scatterData: [ChartSample] = [
    .init(x: "1", y: 2, series: 1), .init(x: "2", y: 4, series: 1),
    .init(x: "3", y: 1, series: 1), .init(x: "4", y: 5, series: 1),
    .init(x: "5", y: 3, series: 1), .init(x: "1", y: 5, series: 2),
    .init(x: "2", y: 2, series: 2), .init(x: "3", y: 4, series: 2),
    .init(x: "4", y: 1, series: 2), .init(x: "5", y: 4, series: 2),
]

// MARK: - Mini chart previews

private struct ColumnPreview: View {
    var body: some View {
        Chart(_barData) { d in
            BarMark(x: .value("X", d.x), y: .value("Y", d.y))
                .foregroundStyle(d.series == 1 ? Color.accentColor : Color.accentColor.opacity(0.5))
        }
        .chartLegend(.hidden)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

private struct BarPreview: View {
    var body: some View {
        Chart(_barData) { d in
            BarMark(x: .value("Y", d.y), y: .value("X", d.x))
                .foregroundStyle(d.series == 1 ? Color.accentColor : Color.accentColor.opacity(0.5))
        }
        .chartLegend(.hidden)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

private struct LinePreview: View {
    var body: some View {
        Chart(_lineData) { d in
            LineMark(x: .value("X", d.x), y: .value("Y", d.y))
                .foregroundStyle(d.series == 1 ? Color.accentColor : Color.accentColor.opacity(0.5))
        }
        .chartLegend(.hidden)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

// Pie preview draws 4 arcs directly — avoids SectorMark (iOS 17+)
private struct PiePreview: View {
    private struct Slice { let degrees: Double; let opacity: Double }
    private let slices: [Slice] = [
        .init(degrees: 144, opacity: 1.0),
        .init(degrees: 90,  opacity: 0.65),
        .init(degrees: 72,  opacity: 0.40),
        .init(degrees: 54,  opacity: 0.20),
    ]
    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2 - 1
            let cx = size.width / 2, cy = size.height / 2
            var start = -90.0
            for slice in slices {
                var p = Path()
                p.move(to: CGPoint(x: cx, y: cy))
                p.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                         startAngle: .degrees(start), endAngle: .degrees(start + slice.degrees), clockwise: false)
                p.closeSubpath()
                ctx.fill(p, with: .color(Color.accentColor.opacity(slice.opacity)))
                start += slice.degrees
            }
        }
    }
}

private struct AreaPreview: View {
    var body: some View {
        Chart(_lineData) { d in
            AreaMark(x: .value("X", d.x), y: .value("Y", d.y))
                .foregroundStyle(d.series == 1 ? Color.accentColor.opacity(0.7) : Color.accentColor.opacity(0.35))
        }
        .chartLegend(.hidden)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

private struct ScatterPreview: View {
    var body: some View {
        Chart(_scatterData) { d in
            PointMark(x: .value("X", d.x), y: .value("Y", d.y))
                .foregroundStyle(d.series == 1 ? Color.accentColor : Color.accentColor.opacity(0.5))
                .symbolSize(30)
        }
        .chartLegend(.hidden)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

@ViewBuilder
private func chartPreview(for type: NativeChartType) -> some View {
    switch type {
    case .column:  ColumnPreview()
    case .bar:     BarPreview()
    case .line:    LinePreview()
    case .pie:     PiePreview()
    case .area:    AreaPreview()
    case .scatter: ScatterPreview()
    }
}

// MARK: - Sheet

/// Native bottom sheet for inserting a chart — user picks chart type then taps Insert.
/// Each cell shows a live mini chart preview rendered with Swift Charts.
struct NativeChartView: View {

    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var selected: NativeChartType = .column

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            dragHandle

            HStack {
                Text("Insert Chart")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(NativeChartType.allCases, id: \.rawValue) { type in
                    chartCell(type)
                }
            }
            .padding(.horizontal, 16)

            actionBar
        }
        .background(Color(.systemBackground))
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
    }

    // MARK: - Subviews

    private var dragHandle: some View {
        Capsule()
            .fill(Color(.systemGray4))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func chartCell(_ type: NativeChartType) -> some View {
        let isSelected = selected == type
        return Button { selected = type } label: {
            VStack(spacing: 6) {
                chartPreview(for: type)
                    .frame(height: 50)
                    .allowsHitTesting(false)
                Text(type.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color(.secondaryLabel))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(
                isSelected ? Color.accentColor.opacity(0.10) : Color(.systemGray6),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button { onCancel() } label: {
                Text("Cancel")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Button { onCommit(selected.rawValue) } label: {
                Text("Insert")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
