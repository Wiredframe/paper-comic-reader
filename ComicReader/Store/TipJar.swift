//
//  TipJar.swift
//  Comic Reader
//
//  Optional one-time "tips" via StoreKit 2 — pure support, they unlock nothing.
//  Products must exist in App Store Connect (or the bundled Tips.storekit config for
//  local testing) under the IDs below.
//

import StoreKit

@MainActor
final class TipJar: ObservableObject {

    /// Product IDs, smallest to largest. Prices are defined in App Store Connect /
    /// Tips.storekit (roughly €1.99 / €4.20 / €6.90).
    static let productIDs = [
        "de.wiredframe.comicreader.tip.small",
        "de.wiredframe.comicreader.tip.medium",
        "de.wiredframe.comicreader.tip.large",
    ]

    @Published private(set) var products: [Product] = []
    @Published private(set) var loadFailed = false
    @Published var purchasingID: String?
    @Published var didTip = false

    /// Load the products once (safe to call repeatedly).
    func load() async {
        guard products.isEmpty else { return }
        do {
            let items = try await Product.products(for: Self.productIDs)
            products = items.sorted { $0.price < $1.price }
            loadFailed = products.isEmpty
        } catch {
            loadFailed = true
        }
    }

    /// Whether to gently surface the tip sheet on launch: once only, after the reader
    /// has been opened a handful of times (reusing AppReview's engagement counter).
    static func shouldAutoPrompt() -> Bool {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "tips.autoPromptShown") else { return false }
        guard defaults.integer(forKey: "review.readerOpens") >= 8 else { return false }
        defaults.set(true, forKey: "tips.autoPromptShown")
        return true
    }

    /// Buy a tip. Consumable, so it's finished immediately; there's nothing to restore.
    func tip(_ product: Product) async {
        purchasingID = product.id
        defer { purchasingID = nil }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    didTip = true
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            // A failed purchase just leaves the sheet as-is; StoreKit shows its own error.
        }
    }
}
