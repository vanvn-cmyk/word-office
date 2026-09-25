import GoogleMobileAds
import UIKit
import Observation

// Swap to your real ad unit ID once provided.
private let kAdUnitID = "ca-app-pub-3940256099942544/5575463023"

// App Open Ads expire after 4 hours per Google policy.
private let kAdMaxAge: TimeInterval = 4 * 3600
private let kCooldown:  TimeInterval = 90
private let kRetryDelay: TimeInterval = 30

@Observable
@MainActor
final class AppOpenAdService: NSObject {

    // MARK: State (readable by callers for debugging)
    private(set) var isLoading  = false
    private(set) var isShowing  = false

    private var loadedAd: AppOpenAd?
    private var loadTime: Date?
    private var lastShownDate: Date?
    private var retryTask: Task<Void, Never>?

    // MARK: - Public API

    /// Call once at launch — starts the first load.
    func start() {
        load()
    }

    /// Show the ad if every condition passes; otherwise no-op.
    /// - Parameter rootVC: the window's `rootViewController`.
    func showIfReady(from rootVC: UIViewController) {
        guard isAdReady else { return }
        guard !isWithinCooldown else { return }
        guard !isPremium else { return }

        isShowing = true
        loadedAd?.present(from: rootVC)
    }

    // MARK: - Load

    private func load() {
        guard !isLoading, loadedAd == nil else { return }
        isLoading = true

        let request = Request()
        AppOpenAd.load(with: kAdUnitID, request: request) { [weak self] ad, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isLoading = false
                if let error {
                    print("[AppOpenAd] Load failed: \(error.localizedDescription)")
                    self.scheduleRetry()
                    return
                }
                self.loadedAd = ad
                self.loadedAd?.fullScreenContentDelegate = self
                self.loadTime = Date()
            }
        }
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(kRetryDelay))
            await MainActor.run { self?.load() }
        }
    }

    // MARK: - Helpers

    private var isAdReady: Bool {
        guard let ad = loadedAd, let loaded = loadTime else { return false }
        let expired = Date().timeIntervalSince(loaded) > kAdMaxAge
        if expired {
            loadedAd = nil
            load()
            return false
        }
        return !isShowing && !isLoading
    }

    private var isWithinCooldown: Bool {
        guard let last = lastShownDate else { return false }
        return Date().timeIntervalSince(last) < kCooldown
    }

    // Stub — replace with real StoreKit receipt check once StoreKit is wired.
    private var isPremium: Bool {
        UserDefaults.standard.bool(forKey: "user.isPremium")
    }
}

// MARK: - FullScreenContentDelegate

extension AppOpenAdService: FullScreenContentDelegate {

    nonisolated func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in self.isShowing = true }
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in
            self.isShowing   = false
            self.loadedAd    = nil
            self.lastShownDate = Date()
            self.load()
        }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd,
                        didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in
            print("[AppOpenAd] Show failed: \(error.localizedDescription)")
            self.isShowing = false
            self.loadedAd  = nil
            self.load()
        }
    }
}
