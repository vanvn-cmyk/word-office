// Sprint 0.3 — text + confidence highlight (§6.4). Extracted out of ScanFlowView
// so the "review recognized text" concern stays its own view, per the file split
// already implied by this file's existence.

import SwiftUI

struct OCRPreviewView: View {
    let results: [OCRResult]
    @Binding var selectedPageIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            pageTabs

            if let result = selectedResult {
                ScrollView {
                    VStack(alignment: .leading, spacing: DSSpacing.sm) {
                        Text(attributedText(for: result))
                            .font(DSFont.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DSSpacing.md)
                            .background(Color.dsBackgroundElevated, in: RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous))

                        if !result.lowConfidenceBlocks.isEmpty {
                            Label(
                                "\(result.lowConfidenceBlocks.count) word\(result.lowConfidenceBlocks.count == 1 ? "" : "s") on this page have low confidence — double-check before saving",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(DSFont.footnote)
                            .foregroundStyle(Color.dsTextPrimary)
                            .padding(DSSpacing.sm)
                            .background(Color.dsStatusWarningBackground, in: RoundedRectangle(cornerRadius: DSRadius.control, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(DSSpacing.md)
    }

    /// `results` only holds successfully-recognized pages, contiguously indexed —
    /// when a page fails OCR, `pageIndex` (the real page number `selectedPageIndex`
    /// is set to, from `pageTabs` below) becomes sparse relative to `results`'
    /// array offsets. Looking up by `pageIndex` instead of subscripting directly
    /// avoids showing the wrong page's — or no — result after a gap.
    private var selectedResult: OCRResult? {
        results.first { $0.pageIndex == selectedPageIndex }
    }

    private var pageTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(results, id: \.pageIndex) { result in
                    let index = result.pageIndex
                    let isSelected = selectedPageIndex == index
                    Button {
                        selectedPageIndex = index
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(result.pageIndex + 1)")
                            if !result.lowConfidenceBlocks.isEmpty {
                                Circle().fill(Color.dsStatusWarning).frame(width: 6, height: 6)
                            }
                        }
                        .font(DSFont.caption.weight(.semibold))
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, 6)
                        .background(isSelected ? Color.dsBrandPrimarySubtle : Color.dsBackgroundElevated, in: Capsule())
                        .foregroundStyle(isSelected ? Color.dsBrandPrimary : Color.dsTextSecondary)
                        .overlay(Capsule().stroke(isSelected ? .clear : Color.dsBorderDefault, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Highlights low-confidence blocks with a background tint directly in the
    /// flowing text (§6.4 — "not a generic warning, the actual suspect words").
    private func attributedText(for result: OCRResult) -> AttributedString {
        var attributed = AttributedString()
        for block in result.blocks {
            var run = AttributedString(block.text + " ")
            if block.confidence < OCRTextBlock.confidenceThreshold {
                run.backgroundColor = Color.dsStatusWarningBackground
            }
            attributed += run
        }
        return attributed
    }
}
