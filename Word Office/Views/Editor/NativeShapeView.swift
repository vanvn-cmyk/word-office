import SwiftUI

/// Shape options shown in the native insert-shape sheet.
enum NativeShapeType: String, CaseIterable {
    case rectangle  = "rect"
    case oval       = "ellipse"
    case triangle   = "triangle"
    case rightArrow = "rightArrow"
    case star       = "star5"
    case heart      = "heart"
    case diamond    = "diamond"
    case cloud      = "cloud"
    case lightning  = "lightningBolt"

    var label: String {
        switch self {
        case .rectangle:  return "Rectangle"
        case .oval:       return "Oval"
        case .triangle:   return "Triangle"
        case .rightArrow: return "Arrow"
        case .star:       return "Star"
        case .heart:      return "Heart"
        case .diamond:    return "Diamond"
        case .cloud:      return "Cloud"
        case .lightning:  return "Lightning"
        }
    }
}

// MARK: - Shape previews

private struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: .init(x: rect.midX, y: rect.minY))
            p.addLine(to: .init(x: rect.maxX, y: rect.midY))
            p.addLine(to: .init(x: rect.midX, y: rect.maxY))
            p.addLine(to: .init(x: rect.minX, y: rect.midY))
            p.closeSubpath()
        }
    }
}

private struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let mid = h * 0.5, tip = w
        let shaftY1 = h * 0.3, shaftY2 = h * 0.7
        let shaftX  = w * 0.65
        return Path { p in
            p.move(to: .init(x: 0, y: shaftY1))
            p.addLine(to: .init(x: shaftX, y: shaftY1))
            p.addLine(to: .init(x: shaftX, y: rect.minY))
            p.addLine(to: .init(x: tip,    y: mid))
            p.addLine(to: .init(x: shaftX, y: rect.maxY))
            p.addLine(to: .init(x: shaftX, y: shaftY2))
            p.addLine(to: .init(x: 0,      y: shaftY2))
            p.closeSubpath()
        }
    }
}

private struct LightningShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        return Path { p in
            p.move(to: .init(x: w * 0.6, y: 0))
            p.addLine(to: .init(x: w * 0.2, y: h * 0.5))
            p.addLine(to: .init(x: w * 0.55, y: h * 0.5))
            p.addLine(to: .init(x: w * 0.4, y: h))
            p.addLine(to: .init(x: w * 0.8, y: h * 0.5))
            p.addLine(to: .init(x: w * 0.45, y: h * 0.5))
            p.closeSubpath()
        }
    }
}

private struct StarShape: Shape {
    let points: Int = 5
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX, cy = rect.midY
        let outerR = min(rect.width, rect.height) / 2
        let innerR = outerR * 0.4
        let total = points * 2
        let pts = (0..<total).map { i -> CGPoint in
            let angle = (CGFloat(i) * .pi / CGFloat(points)) - .pi / 2
            let r = i.isMultiple(of: 2) ? outerR : innerR
            return .init(x: cx + r * cos(angle), y: cy + r * sin(angle))
        }
        return Path { p in
            guard let first = pts.first else { return }
            p.move(to: first)
            pts.dropFirst().forEach { p.addLine(to: $0) }
            p.closeSubpath()
        }
    }
}

private struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to:    .init(x: w * 0.3,  y: h * 0.85))
        p.addLine(to: .init(x: w * 0.1,  y: h * 0.85))
        p.addArc(center: .init(x: w * 0.15, y: h * 0.65), radius: w * 0.14,
                 startAngle: .degrees(90),  endAngle: .degrees(210), clockwise: false)
        p.addArc(center: .init(x: w * 0.3,  y: h * 0.45), radius: w * 0.18,
                 startAngle: .degrees(200), endAngle: .degrees(310), clockwise: false)
        p.addArc(center: .init(x: w * 0.55, y: h * 0.35), radius: w * 0.22,
                 startAngle: .degrees(230), endAngle: .degrees(340), clockwise: false)
        p.addArc(center: .init(x: w * 0.78, y: h * 0.5),  radius: w * 0.16,
                 startAngle: .degrees(310), endAngle: .degrees(90),  clockwise: false)
        p.addLine(to: .init(x: w * 0.7, y: h * 0.85))
        p.closeSubpath()
        return p
    }
}

@ViewBuilder
private func shapePreview(for type: NativeShapeType, color: Color) -> some View {
    switch type {
    case .rectangle:
        RoundedRectangle(cornerRadius: 3).fill(color)
    case .oval:
        Ellipse().fill(color)
    case .triangle:
        Triangle().fill(color)
    case .rightArrow:
        ArrowShape().fill(color)
    case .star:
        StarShape().fill(color)
    case .heart:
        Image(systemName: "heart.fill").resizable().scaledToFit().foregroundStyle(color)
    case .diamond:
        DiamondShape().fill(color)
    case .cloud:
        CloudShape().fill(color)
    case .lightning:
        LightningShape().fill(color)
    }
}

// MARK: - Triangle built-in (iOS)

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: .init(x: rect.midX, y: rect.minY))
            p.addLine(to: .init(x: rect.maxX, y: rect.maxY))
            p.addLine(to: .init(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

// MARK: - Sheet

/// Native bottom sheet for inserting a shape — user picks shape type then taps Insert.
/// Each cell shows a rendered SwiftUI shape preview.
struct NativeShapeView: View {

    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var selected: NativeShapeType = .rectangle

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            dragHandle

            HStack {
                Text("Insert Shape")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(NativeShapeType.allCases, id: \.rawValue) { type in
                    shapeCell(type)
                }
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 0)

            actionBar
        }
        .background(Color(.systemBackground))
        .presentationDetents([.height(460)])
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

    private func shapeCell(_ type: NativeShapeType) -> some View {
        let isSelected = selected == type
        let fillColor: Color = isSelected ? Color.accentColor : Color(.label).opacity(0.75)
        return Button { selected = type } label: {
            VStack(spacing: 6) {
                shapePreview(for: type, color: fillColor)
                    .frame(height: 44)
                    .padding(.horizontal, 10)
                    .allowsHitTesting(false)
                Text(type.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color(.secondaryLabel))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
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
