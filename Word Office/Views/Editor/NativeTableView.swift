import SwiftUI

/// Native bottom sheet for inserting a table — user taps or drags across a grid
/// to choose rows × columns, then taps Insert.
///
/// Safe insertion path: the selected dimensions are passed to
/// `OfficeEditorViewController.insertTable(rows:cols:)`, which calls ONLYOFFICE
/// APIs directly without falling back to `_clickOOBtn` (the OO toolbar-button
/// click that opens OO's native dialog, known to crash WKWebView on iOS).
struct NativeTableView: View {

    let onCommit: (Int, Int) -> Void
    let onCancel: () -> Void

    private static let maxRows = 6
    private static let maxCols = 6

    @State private var selectedRow = 3
    @State private var selectedCol = 3

    var body: some View {
        VStack(spacing: 0) {
            dragHandle

            HStack {
                Text("Insert Table")
                    .font(.headline)
                    .foregroundStyle(Color.dsTextPrimary)
                Spacer()
                Button("Cancel") { onCancel() }
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            Text("\(selectedRow) × \(selectedCol) Table")
                .font(.subheadline)
                .foregroundStyle(Color.dsTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            tableGrid
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            actionBar
        }
        .background(Color.dsBackgroundElevated)
        .presentationDetents([.height(330)])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Grid

    private var tableGrid: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 4
            let cols = Self.maxCols
            let rows = Self.maxRows
            let cellW = (geo.size.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
            let cellH = cellW

            ZStack(alignment: .topLeading) {
                VStack(spacing: spacing) {
                    ForEach(1...rows, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(1...cols, id: \.self) { col in
                                let isSelected = row <= selectedRow && col <= selectedCol
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.dsBackgroundTertiary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .strokeBorder(
                                                isSelected ? Color.accentColor : Color.dsBorderSubtle,
                                                lineWidth: isSelected ? 1.5 : 1
                                            )
                                    )
                                    .frame(width: cellW, height: cellH)
                            }
                        }
                    }
                }

                // Invisible drag/tap overlay sized to the full grid
                Color.clear
                    .frame(width: geo.size.width,
                           height: (cellH + spacing) * CGFloat(rows) - spacing)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                let col = max(1, min(cols,
                                    Int(value.location.x / (cellW + spacing)) + 1))
                                let row = max(1, min(rows,
                                    Int(value.location.y / (cellH + spacing)) + 1))
                                selectedCol = col
                                selectedRow = row
                            }
                    )
                    .onTapGesture(coordinateSpace: .local) { location in
                        let col = max(1, min(cols, Int(location.x / (cellW + spacing)) + 1))
                        let row = max(1, min(rows, Int(location.y / (cellH + spacing)) + 1))
                        selectedCol = col
                        selectedRow = row
                    }
            }
        }
        .frame(height: 140)
    }

    // MARK: - Chrome

    private var dragHandle: some View {
        Capsule()
            .fill(Color.dsBorderDefault)
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 16)
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                onCommit(selectedRow, selectedCol)
            } label: {
                Text("Insert \(selectedRow) × \(selectedCol) Table")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.dsTextOnBrand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }
}
