import Foundation
import Observation
import StoreKit

private let kWeeklyID = "com.docx.officeeditor.pdfeditor.week"
private let kYearlyID  = "com.docx.officeeditor.pdfeditor.year"

@Observable
@MainActor
final class PaywallViewModel {

    struct Offer: Identifiable, Hashable, Sendable {
        let id: String          // matches App Store product ID
        let title: String
        let period: String
        let trialLabel: String? // non-nil when offer has a free trial
    }

    enum Status: Sendable, Equatable {
        case idle
        case loading
        case purchasing
        case restoring
        case succeeded
        case failed(String)
    }

    // MARK: State

    let offers: [Offer] = [
        Offer(id: kWeeklyID, title: "Weekly",  period: "Then billed weekly",    trialLabel: "3-DAY FREE"),
        Offer(id: kYearlyID,  title: "Yearly",  period: "Billed once a year",    trialLabel: nil),
    ]

    var selectedOfferID: String = kYearlyID
    private(set) var status: Status = .idle

    /// Fetched StoreKit products keyed by product ID.
    private var storeProducts: [String: Product] = [:]

    // MARK: - Derived

    var selectedOffer: Offer? {
        offers.first(where: { $0.id == selectedOfferID })
    }

    var isBusy: Bool {
        status == .purchasing || status == .restoring || status == .loading
    }

    var ctaLabel: String {
        switch status {
        case .loading:    return "Loading…"
        case .purchasing: return "Processing…"
        case .restoring:  return "Restoring…"
        case .succeeded:  return "Welcome to Premium 🎉"
        case .failed:     return "Try Again"
        case .idle:
            return selectedOffer?.trialLabel != nil ? "Start Free Trial" : "Get Yearly Access"
        }
    }

    /// Returns the localised display price for `offerID`, or "—" while loading.
    func displayPrice(for offerID: String) -> String {
        storeProducts[offerID]?.displayPrice ?? "—"
    }

    // MARK: - Load products

    func loadProducts() async {
        guard storeProducts.isEmpty else { return }
        status = .loading
        do {
            let products = try await Product.products(for: [kWeeklyID, kYearlyID])
            for product in products { storeProducts[product.id] = product }
        } catch {
            print("[Paywall] Product fetch failed: \(error)")
        }
        status = .idle
    }

    // MARK: - Purchase

    func purchase() async {
        guard let offer = selectedOffer,
              let product = storeProducts[offer.id],
              !isBusy else { return }

        status = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    UserDefaults.standard.set(true, forKey: "user.isPremium")
                    status = .succeeded
                case .unverified(_, let error):
                    status = .failed("Verification failed: \(error.localizedDescription)")
                }
            case .pending:
                status = .idle
            case .userCancelled:
                status = .idle
            @unknown default:
                status = .idle
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: - Restore

    func restore() async {
        guard !isBusy else { return }
        status = .restoring
        do {
            try await AppStore.sync()
            var hasPremium = false
            for await result in Transaction.currentEntitlements {
                if case .verified(let tx) = result,
                   [kWeeklyID, kYearlyID].contains(tx.productID) {
                    await tx.finish()
                    hasPremium = true
                }
            }
            UserDefaults.standard.set(hasPremium, forKey: "user.isPremium")
            status = hasPremium ? .succeeded : .idle
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func clearError() {
        if case .failed = status { status = .idle }
    }
}
