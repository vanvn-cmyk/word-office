import Foundation
import Observation

/// Owns paywall presentation state — offer catalogue, current selection,
/// purchase / restore progress. StoreKit is intentionally NOT wired here
/// yet; `PaywallView` calls into these stubs so the UI can be exercised
/// while the real product IDs and receipt-validation service arrive
/// later.
///
/// The catalogue is a static two-tier stub (Monthly / Yearly) matching
/// the MVP paywall variant `iap_v1` in `product-strategy-master.md` — a
/// single tier with a highlighted annual save. When the remote-config
/// paywall engine ships (variants `iap_v1`…`iap_v7`), replace
/// `Self.defaultOffers` with a call into the config service; the view
/// binds to `offers` unchanged.
@Observable
@MainActor
final class PaywallViewModel {
    /// One purchasable product surfaced on the paywall. Kept intentionally
    /// small — display-only fields plus a stable `id` that later maps to
    /// the App Store `Product.id`. No `Product` reference so the model
    /// stays free of StoreKit imports until wiring day.
    struct Offer: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let price: String
        let period: String
        let secondaryLine: String?
        let highlight: String?
        let isRecommended: Bool
    }

    /// Terminal states of a purchase / restore attempt so the view can
    /// switch between the CTA button, an in-flight spinner, and a
    /// dismissable success / error state without owning the strings.
    enum Status: Sendable, Equatable {
        case idle
        case purchasing
        case restoring
        case succeeded
        case failed(String)
    }

    let offers: [Offer]
    var selectedOfferID: String
    private(set) var status: Status = .idle

    init(offers: [Offer]? = nil) {
        // `Self.defaultOffers` can't be used as a default arg here —
        // Swift disallows covariant `Self` in default expressions AND
        // `defaultOffers` is `@MainActor`-isolated because the class
        // is (Swift 6 strict-concurrency), so it can't be read from a
        // nonisolated default expression. Fall back inside the body.
        let resolved = offers ?? PaywallViewModel.defaultOffers
        self.offers = resolved
        // Recommended offer is preselected — matches the "yearly-first"
        // conversion pattern the strategy doc calls out (Persona anchor
        // 35–44 skews toward committed annual plans over weekly hooks).
        self.selectedOfferID = resolved.first(where: { $0.isRecommended })?.id
            ?? resolved.first?.id
            ?? ""
    }

    /// Selected offer resolved back to the model — nil when the catalogue
    /// is empty, which the view treats as "no offers available".
    var selectedOffer: Offer? {
        offers.first(where: { $0.id == selectedOfferID })
    }

    /// CTA label switches on both `status` and whether the selected offer
    /// carries a trial hint; keeping it in the VM stops the view from
    /// duplicating the switch every time the CTA renders.
    var ctaLabel: String {
        switch status {
        case .purchasing:   return "Processing…"
        case .restoring:    return "Restoring…"
        case .succeeded:    return "Welcome to Premium"
        case .failed:       return "Try Again"
        case .idle:
            guard let offer = selectedOffer else { return "Continue" }
            return offer.secondaryLine?.lowercased().contains("free") == true
                ? "Start Free Trial"
                : "Continue"
        }
    }

    var isBusy: Bool {
        if case .purchasing = status { return true }
        if case .restoring = status { return true }
        return false
    }

    // MARK: - Actions

    /// Purchase the currently selected offer.
    /// TODO(paywall): swap the stub delay + hardcoded success for a real
    /// StoreKit 2 `product.purchase()` call once product IDs are
    /// provisioned in App Store Connect.
    func purchase() async {
        guard let offer = selectedOffer, !isBusy else { return }
        status = .purchasing
        do {
            try await Task.sleep(for: .milliseconds(700))
            _ = offer
            status = .succeeded
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Restore previously purchased entitlements.
    /// TODO(paywall): wire `AppStore.sync()` + a receipt-refresh pass
    /// once the entitlement store lands.
    func restore() async {
        guard !isBusy else { return }
        status = .restoring
        do {
            try await Task.sleep(for: .milliseconds(500))
            status = .idle
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func clearError() {
        if case .failed = status { status = .idle }
    }

    // MARK: - Catalogue stub

    /// Placeholder offers rendered until the remote-config paywall
    /// engine (strategy doc row 1 — seven `iap_v*` variants) ships.
    /// TODO(paywall): replace with values pulled from `IKRemoteConfig`
    /// (`iap_product_id_config`), keyed on the active variant.
    static let defaultOffers: [Offer] = [
        Offer(
            id: "com.wordoffice.premium.monthly",
            title: "Monthly",
            price: "$4.99",
            period: "per month",
            secondaryLine: "Cancel anytime",
            highlight: nil,
            isRecommended: true
        )
    ]
}
