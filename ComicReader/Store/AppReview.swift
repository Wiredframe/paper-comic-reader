//
//  AppReview.swift
//  Comic Reader
//
//  Asks for an App Store rating "every now and then" after some real reading, and
//  provides the direct "Rate on the App Store" link for Settings.
//

import StoreKit
import UIKit

enum AppInfo {
    /// The app's numeric App Store ID. Fill this in once the app has a listing —
    /// until then the store links just won't resolve.
    static let appStoreID = "0000000000"

    static var appStoreURL: URL { URL(string: "https://apps.apple.com/app/id\(appStoreID)")! }
    static var writeReviewURL: URL {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!
    }
}

@MainActor
enum AppReview {
    private static let opensKey = "review.readerOpens"
    private static let lastVersionKey = "review.lastPromptVersion"

    /// Count a meaningful engagement (a comic was read). After a few of them — and
    /// again occasionally — hand off to the system prompt. iOS decides whether to
    /// actually show it and caps it at three prompts a year; there is no API to read
    /// whether the user already rated, so we defer entirely to the system and just
    /// avoid asking twice on the same build.
    static func registerReaderOpen() {
        let defaults = UserDefaults.standard
        let opens = defaults.integer(forKey: opensKey) + 1
        defaults.set(opens, forKey: opensKey)
        guard opens == 4 || opens % 25 == 0 else { return }
        let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        guard defaults.string(forKey: lastVersionKey) != version else { return }
        defaults.set(version, forKey: lastVersionKey)
        requestReview()
    }

    /// The system "How many stars?" prompt (may or may not appear — the OS decides).
    static func requestReview() {
        guard let scene = activeScene else { return }
        AppStore.requestReview(in: scene)
    }

    /// Opens the App Store review page directly (from the Settings button).
    static func openWriteReview() {
        UIApplication.shared.open(AppInfo.writeReviewURL)
    }

    private static var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
}
