import SwiftUI

extension Color {
    // MARK: - Brand
    static let dsBrandPrimary              = Color("BrandPrimary")
    static let dsBrandPrimaryPressed       = Color("BrandPrimaryPressed")
    static let dsBrandPrimarySubtle        = Color("BrandPrimarySubtle")
    static let dsBrandPrimarySubtlePressed = Color("BrandPrimarySubtlePressed")
    static let dsBrandBorder               = Color("BrandBorder")
    static let dsBrandText                 = Color("BrandText")

    // MARK: - Background
    static let dsBackgroundPrimary   = Color("BackgroundPrimary")
    static let dsBackgroundSecondary = Color("BackgroundSecondary")
    static let dsBackgroundTertiary  = Color("BackgroundTertiary")
    static let dsBackgroundElevated  = Color("BackgroundElevated")

    // MARK: - Surface
    static let dsSurfacePrimary   = Color("SurfacePrimary")
    static let dsSurfaceSecondary = Color("SurfaceSecondary")
    static let dsSurfaceTertiary  = Color("SurfaceTertiary")
    static let dsSurfaceSelected  = Color("SurfaceSelected")
    static let dsSurfaceHover     = Color("SurfaceHover")
    static let dsSurfacePressed   = Color("SurfacePressed")
    static let dsSurfaceDisabled  = Color("SurfaceDisabled")

    // MARK: - Text
    static let dsTextPrimary   = Color("TextPrimary")
    static let dsTextSecondary = Color("TextSecondary")
    static let dsTextTertiary  = Color("TextTertiary")
    static let dsTextDisabled  = Color("TextDisabled")
    static let dsTextOnBrand   = Color("TextOnBrand")
    static let dsTextLink      = Color("TextLink")

    // MARK: - Border
    static let dsBorderSubtle  = Color("BorderSubtle")
    static let dsBorderDefault = Color("BorderDefault")
    static let dsBorderStrong  = Color("BorderStrong")
    static let dsBorderFocused = Color("BorderFocused")

    // MARK: - Status
    static let dsStatusSuccess           = Color("StatusSuccess")
    static let dsStatusSuccessBackground = Color("StatusSuccessBackground")
    static let dsStatusSuccessBorder     = Color("StatusSuccessBorder")
    static let dsStatusWarning           = Color("StatusWarning")
    static let dsStatusWarningBackground = Color("StatusWarningBackground")
    static let dsStatusWarningBorder     = Color("StatusWarningBorder")
    static let dsStatusError             = Color("StatusError")
    static let dsStatusErrorBackground   = Color("StatusErrorBackground")
    static let dsStatusErrorBorder       = Color("StatusErrorBorder")

    // MARK: - Document type
    static let dsDocumentWord         = Color("DocumentWord")
    static let dsDocumentSpreadsheet  = Color("DocumentSpreadsheet")
    static let dsDocumentPresentation = Color("DocumentPresentation")
    static let dsDocumentPDF          = Color("DocumentPDF")
    static let dsDocumentImage        = Color("DocumentImage")
    static let dsDocumentGeneric      = Color("DocumentGeneric")

    // MARK: - Document workspace
    static let dsDocumentCanvas     = Color("DocumentCanvas")
    static let dsDocumentPage       = Color("DocumentPage")
    static let dsDocumentPageBorder = Color("DocumentPageBorder")

    // MARK: - Overlay
    static let dsOverlayScrim  = Color("OverlayScrim")
    static let dsOverlayStrong = Color("OverlayStrong")

    // MARK: - Selection
    static let dsSelectionBackground = Color("SelectionBackground")
    static let dsSelectionBorder     = Color("SelectionBorder")
    static let dsSelectionText       = Color("SelectionText")

    // MARK: - Button disabled
    static let dsButtonDisabledBackground = Color("ButtonDisabledBackground")
    static let dsButtonDisabledText       = Color("ButtonDisabledText")

    // MARK: - Premium
    // Apple's own systemYellow → systemOrange pair (light: FFCC00 → FF9500,
    // dark: FFD60A → FF9F0A) — the gold/amber gradient Apple's first-party
    // apps use for subscription/premium badges. `dsStatusWarning` looked
    // like the reused "warning brown" it actually is (A75D00) when tried
    // here instead; this is its own token so Premium never drifts if
    // Warning's hex changes.
    static let dsPremiumGoldStart = Color("PremiumGoldStart")
    static let dsPremiumGoldEnd   = Color("PremiumGoldEnd")
}
