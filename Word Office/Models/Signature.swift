// Session 12 (2026-09-04) — Tier 1 (drawing image) for MVP. Tier 2 (PKI
// cert-based signing) deferred to Phase 2 per spec §9.1 "ship first".

import Foundation

/// A hand-drawn signature captured via PencilKit and rendered to a PNG
/// image. `Data` (not `UIImage`) so the model stays `Sendable` and can
/// cross actor boundaries into the stamping service without a wrapper.
///
/// No PII stored beyond the image bytes — the signature never leaves the
/// device (memory + the destination PDF only). See the on-device disclaimer
/// shown to the user on the canvas screen.
struct Signature: Identifiable, Sendable, Hashable {
    let id: UUID
    /// PNG-encoded image bytes with transparent background — so it composites
    /// cleanly over any PDF page content, not just white paper.
    let imageData: Data
    let createdAt: Date

    init(id: UUID = UUID(), imageData: Data, createdAt: Date = .now) {
        self.id = id
        self.imageData = imageData
        self.createdAt = createdAt
    }
}
