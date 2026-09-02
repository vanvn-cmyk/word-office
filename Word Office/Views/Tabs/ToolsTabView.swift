import SwiftUI

/// Tools home — per the approved `Wireframe/PDFTools-Mockup-v2.html`: Scan & OCR
/// as a standalone hero (not a 1-item category), Convert as 2 paired cards
/// (Office⇄PDF, Image⇄PDF), Organize as a grouped list (Merge/Split).
struct ToolsTabView: View {
    let container: DependencyContainer

    @State private var pdfToolsVM: PDFToolsViewModel?
    @State private var ocrVM: OCRViewModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    scanHero

                    sectionHeader("Convert", systemImage: "arrow.left.arrow.right")
                    convertPairs

                    sectionHeader("Organize", systemImage: "doc.on.doc")
                    organizeList
                }
                .padding(.vertical, DSSpacing.md)
            }
            .background(Color.dsBackgroundSecondary)
            .navigationTitle("Tools")
            .navigationDestination(for: PDFToolDestination.self) { destination in
                destinationView(for: destination)
            }
        }
        .task {
            if pdfToolsVM == nil { pdfToolsVM = container.makePDFToolsViewModel() }
            if ocrVM == nil { ocrVM = container.makeOCRViewModel() }
        }
    }

    // MARK: - Scan hero

    private var scanHero: some View {
        NavigationLink(value: PDFToolDestination.scan) {
            HStack(spacing: DSSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
                        .fill(Color.dsBrandPrimary.gradient)
                    Image(systemName: "viewfinder")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.dsTextOnBrand)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.dsStatusSuccess).frame(width: 5, height: 5)
                        Text("Scan & OCR").font(DSFont.headline).foregroundStyle(Color.dsTextPrimary)
                    }
                    Text("On-device — camera, photos, or PDF → editable text")
                        .font(DSFont.footnote)
                        .foregroundStyle(Color.dsTextSecondary)
                }

                Spacer(minLength: DSSpacing.xs)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsTextTertiary)
            }
            .padding(DSSpacing.md)
            .background(
                LinearGradient(
                    colors: [Color.dsBrandPrimarySubtle, Color.dsBackgroundElevated],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
                    .stroke(Color.dsBorderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DSSpacing.md)
    }

    // MARK: - Convert (2 paired cards, §7.4)

    private var convertPairs: some View {
        VStack(spacing: DSSpacing.xs) {
            pairCard(.officeToPDF, .pdfToWord)
            pairCard(.pdfToImage, .imageToPDF)
        }
        .padding(.horizontal, DSSpacing.md)
    }

    private func pairCard(_ left: ConvertDirection, _ right: ConvertDirection) -> some View {
        HStack(spacing: 0) {
            convertHalf(left)
            Divider()
            convertHalf(right)
        }
        .background(Color.dsBackgroundElevated, in: RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.large, style: .continuous)
                .stroke(Color.dsBorderSubtle, lineWidth: 1)
                .allowsHitTesting(false)
        )
    }

    private func convertHalf(_ direction: ConvertDirection) -> some View {
        NavigationLink(value: PDFToolDestination.convert(direction)) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                convertIconRow(direction)
                Text(direction.title).font(DSFont.subheadline.weight(.semibold)).foregroundStyle(Color.dsTextPrimary)
                Text(convertSubtitle(direction))
                    .font(DSFont.caption)
                    .foregroundStyle(Color.dsTextTertiary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func convertSubtitle(_ direction: ConvertDirection) -> String {
        switch direction {
        case .officeToPDF: "Word, Excel, PowerPoint"
        case .pdfToWord:   "Text only, no formatting"
        case .pdfToImage:  "Export pages as PNG"
        case .imageToPDF:  "Combine photos"
        }
    }

    @ViewBuilder
    private func convertIconRow(_ direction: ConvertDirection) -> some View {
        HStack(spacing: 6) {
            miniBadge(convertLeadingIcon(direction), tint: convertLeadingTint(direction))
            Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.dsTextTertiary)
            miniBadge(convertTrailingIcon(direction), tint: convertTrailingTint(direction))
        }
    }

    private func convertLeadingIcon(_ d: ConvertDirection) -> String {
        switch d {
        case .officeToPDF: "doc.on.doc.fill"
        case .pdfToWord, .pdfToImage: "doc.fill"
        case .imageToPDF: "photo.fill"
        }
    }
    private func convertTrailingIcon(_ d: ConvertDirection) -> String {
        switch d {
        case .officeToPDF, .imageToPDF: "doc.fill"
        case .pdfToWord: "doc.text.fill"
        case .pdfToImage: "photo.fill"
        }
    }
    private func convertLeadingTint(_ d: ConvertDirection) -> Color {
        switch d {
        case .officeToPDF: .dsDocumentWord
        case .pdfToWord, .pdfToImage: .dsDocumentPDF
        case .imageToPDF: .dsDocumentImage
        }
    }
    private func convertTrailingTint(_ d: ConvertDirection) -> Color {
        switch d {
        case .officeToPDF, .imageToPDF: .dsDocumentPDF
        case .pdfToWord: .dsDocumentWord
        case .pdfToImage: .dsDocumentImage
        }
    }

    private func miniBadge(_ systemImage: String, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous)
                .fill(tint.opacity(0.14))
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: 28, height: 28)
    }

    // MARK: - Organize (Merge/Split, §7.1)

    private var organizeList: some View {
        VStack(spacing: 0) {
            organizeRow(
                destination: .merge,
                icon: "doc.on.doc.fill",
                title: "Merge PDFs",
                subtitle: "Combine 2 or more files into one"
            )
            Divider().padding(.leading, DSSpacing.md + DSSize.fileIcon + DSSpacing.sm)
            organizeRow(
                destination: .split,
                icon: "square.split.2x1",
                title: "Split PDF",
                subtitle: "Break one file into page ranges"
            )
        }
        .background(Color.dsBackgroundElevated, in: RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                .stroke(Color.dsBorderSubtle, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .padding(.horizontal, DSSpacing.md)
    }

    private func organizeRow(destination: PDFToolDestination, icon: String, title: String, subtitle: String) -> some View {
        NavigationLink(value: destination) {
            HStack(spacing: DSSpacing.sm) {
                miniBadge(icon, tint: .dsDocumentPDF)
                    .frame(width: DSSize.fileIcon, height: DSSize.fileIcon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(DSFont.headline).foregroundStyle(Color.dsTextPrimary)
                    Text(subtitle).font(DSFont.footnote).foregroundStyle(Color.dsTextTertiary)
                }
                Spacer(minLength: DSSpacing.xs)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsTextTertiary)
            }
            .padding(DSSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.dsBrandPrimary)
            Text(title).font(DSFont.headline).foregroundStyle(Color.dsTextPrimary)
        }
        .padding(.horizontal, DSSpacing.md)
    }

    // MARK: - Destinations

    @ViewBuilder
    private func destinationView(for destination: PDFToolDestination) -> some View {
        if let pdfToolsVM {
            switch destination {
            case .merge:
                MergeView(viewModel: pdfToolsVM)
            case .split:
                SplitView(viewModel: pdfToolsVM)
            case .convert(let direction):
                ConvertFlowView(viewModel: pdfToolsVM, direction: direction)
            case .scan:
                if let ocrVM {
                    ScanFlowView(viewModel: ocrVM)
                } else {
                    ProgressView()
                }
            }
        } else {
            ProgressView()
        }
    }
}

#Preview { ToolsTabView(container: DependencyContainer()) }
