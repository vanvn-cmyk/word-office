import ImageIO
import SwiftUI
import UIKit

/// Result of a completed tool operation — the parent decides how to
/// present the output. Single editable file → the in-app editor.
/// Multi-file or non-editable batch (images) → `ToolResultGalleryView`.
///
/// Kept out of the closures' inferred type so each tool view spells the
/// decision explicitly (Merge always `.openInEditor`, PDF→Image always
/// `.presentGallery`, Split branches on count, and so on).
enum ToolCompletion {
    case openInEditor(URL)
    case presentGallery([URL])
}

/// Bottom-sheet gallery for multi-output tool results. Layout auto-picks
/// between a 2-column thumbnail grid (all-image batches — PDF→Image) and
/// list rows (mixed types or documents — Split N>1, Scan PDF+DOCX). The
/// action bar exposes `Save All` (system document picker) and `Share All`
/// (native `ShareLink`). Tapping a tile/row asks the parent to open that
/// one file, then dismisses.
///
/// Session 10 gap fix (2026-09-04) — was the "toast + stay at picker"
/// bug reported for PDF→Image; solution generalised to every multi-file
/// tool output so the tools tab has a single consistent completion story.
struct ToolResultGalleryView: View {
    let urls: [URL]
    /// Called with the tapped URL. The parent typically dismisses this
    /// sheet then presents its own editor for that file — sequencing
    /// two sheets is the parent's job (via `.sheet(item:onDismiss:)`).
    let onOpenFile: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingExporter = false
    /// Filesize labels precomputed off-main when the sheet opens. Body
    /// renders `sizeLabels[url]` synchronously — no per-frame disk read.
    /// Pre-fix: `url.resourceValues(forKeys: [.fileSizeKey])` ran during
    /// body eval for every visible row/tile, which was a real hitch risk
    /// once a PDF→Image export produced 20+ pages worth of PNGs.
    @State private var sizeLabels: [URL: String] = [:]
    /// ImageIO-downsampled thumbnails cached in memory. `AsyncImage(url:)`
    /// would load the full-resolution PNG for every tile — a 2x-scale
    /// page export runs a few MB per image, so 20 pages balloons past
    /// 40 MB just for the grid. `CGImageSourceCreateThumbnailAtIndex`
    /// with a `kCGImageSourceThumbnailMaxPixelSize` cap keeps memory
    /// bounded regardless of source dimensions.
    @State private var thumbnails: [URL: UIImage] = [:]

    /// Grid layout only fires when EVERY output is a recognisable image
    /// extension. Mixed batches (Scan → 1 PDF + 1 DOCX) fall through to
    /// the list branch even if one item happens to be an image, because a
    /// half-thumbnail-half-icon grid reads worse than a uniform list.
    private var isAllImages: Bool {
        !urls.isEmpty && urls.allSatisfy { ImageExtension.recognises($0) }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Results")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
                .safeAreaInset(edge: .bottom) { actionBar }
                .background(Color.dsBackgroundSecondary)
                .sheet(isPresented: $showingExporter) {
                    DocumentPickerExporter(urls: urls)
                }
                .task(id: urls) { await preloadMetadata() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder private var content: some View {
        if isAllImages {
            gridLayout
        } else {
            listLayout
        }
    }

    // MARK: - Grid (all-image)

    private var gridLayout: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: DSSpacing.sm),
                    GridItem(.flexible(), spacing: DSSpacing.sm)
                ],
                spacing: DSSpacing.sm
            ) {
                ForEach(urls, id: \.self) { url in
                    Button { openAndDismiss(url) } label: {
                        imageTile(url)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(url.lastPathComponent))
                }
            }
            .padding(DSSpacing.md)
        }
    }

    private func imageTile(_ url: URL) -> some View {
        VStack(spacing: 0) {
            thumbnailView(url)
                .frame(maxWidth: .infinity)
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .clipped()

            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(DSFont.caption)
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(sizeLabels[url] ?? " ")
                    .font(DSFont.caption)
                    .foregroundStyle(Color.dsTextTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DSSpacing.xs)
            .padding(.vertical, DSSpacing.xxs)
        }
        .background(Color.dsBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                .stroke(Color.dsBorderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder private func thumbnailView(_ url: URL) -> some View {
        if let image = thumbnails[url] {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            thumbFallback(systemImage: "photo")
        }
    }

    private func thumbFallback(systemImage: String) -> some View {
        ZStack {
            Color.dsBackgroundSecondary
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(Color.dsTextTertiary)
        }
    }

    // MARK: - List (mixed/docs)

    private var listLayout: some View {
        List {
            ForEach(urls, id: \.self) { url in
                Button { openAndDismiss(url) } label: {
                    fileRow(url)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.dsBackgroundElevated)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func fileRow(_ url: URL) -> some View {
        HStack(spacing: DSSpacing.sm) {
            fileBadge(url)
                .frame(width: DSSize.fileIcon, height: DSSize.fileIcon)

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(url.lastPathComponent)
                    .font(DSFont.headline)
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let size = sizeLabels[url] {
                    Text(size)
                        .font(DSFont.subheadline)
                        .foregroundStyle(Color.dsTextSecondary)
                }
            }

            Spacer(minLength: DSSpacing.xs)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.dsTextTertiary)
        }
        .contentShape(Rectangle())
    }

    /// Falls back to a generic PDF badge when UTI detection returns nil —
    /// tools currently never produce a truly unknown output, so this is a
    /// belt-and-braces default rather than a real branch users hit.
    @ViewBuilder private func fileBadge(_ url: URL) -> some View {
        if ImageExtension.recognises(url) {
            imageBadge
        } else if let kind = DocumentKind.fromUTI(url: url) {
            DocumentKindIcon(kind: kind)
        } else {
            DocumentKindIcon(kind: .pdf)
        }
    }

    private var imageBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous)
                .fill(Color.dsDocumentImage.opacity(0.12))
            Image(systemName: "photo.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.dsDocumentImage)
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: DSSpacing.sm) {
            Button {
                showingExporter = true
            } label: {
                Label("Save All", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(Color.dsBrandPrimary)

            ShareLink(items: urls, preview: { url in
                SharePreview(Text(url.lastPathComponent))
            }) {
                Label("Share All", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.dsBrandPrimary)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(.thinMaterial)
    }

    // MARK: - Helpers

    /// Fires the parent's open-file callback then dismisses this sheet.
    /// The parent is expected to defer the actual editor presentation to
    /// its own `.sheet(item:onDismiss:)` so the two sheets don't race —
    /// see `ToolsTabView.showGallery(_:)`.
    private func openAndDismiss(_ url: URL) {
        onOpenFile(url)
        dismiss()
    }

    /// Reads filesize + generates image thumbnails off-main so `body` stays
    /// synchronous. Runs once per unique `urls` set (via `.task(id: urls)`).
    /// Errors are swallowed silently — a missing size label just renders as
    /// blank space, and a missing thumbnail falls back to a `photo` icon,
    /// neither is worth an error banner.
    private func preloadMetadata() async {
        let targets = urls
        let cap = Self.thumbnailMaxPixelSize
        let results: [(URL, String?, UIImage?)] = await Task.detached(priority: .utility) {
            targets.map { url in
                let size: String? = {
                    guard
                        let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                        let bytes = values.fileSize
                    else { return nil }
                    return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
                }()
                let thumb: UIImage? = ImageExtension.recognises(url) ? Self.thumbnail(for: url, maxDimension: cap) : nil
                return (url, size, thumb)
            }
        }.value
        for (url, size, thumb) in results {
            if let size { sizeLabels[url] = size }
            if let thumb { thumbnails[url] = thumb }
        }
    }

    /// 2x the tile width at the largest phone (~400px) so the downsample
    /// still looks crisp on a Retina display without blowing memory —
    /// 600px squared is <1 MB per thumbnail regardless of source PNG size.
    nonisolated static let thumbnailMaxPixelSize: Int = 600

    nonisolated private static func thumbnail(for url: URL, maxDimension: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Whitelist of image extensions the gallery treats as image results.
/// Kept explicit rather than delegating to `UTType` per-URL because
/// `isAllImages` branches once per body render — an extension-string
/// lookup is cheaper than a UTI conformance check across the whole set.
enum ImageExtension {
    static let recognized: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "webp", "gif", "tiff"]

    static func recognises(_ url: URL) -> Bool {
        recognized.contains(url.pathExtension.lowercased())
    }
}
