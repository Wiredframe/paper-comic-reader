//
//  AppAppearance.swift
//  Comic Reader
//
//  The user's chosen interface appearance (System / Light / Dark), persisted as a
//  string under "app.appearance" (@AppStorage). Drives `.preferredColorScheme` at the
//  app root. Default is System (follow the device); users who already picked a theme
//  keep their choice.
//

import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "app.appearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// nil → follow the system; otherwise force that scheme.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    static func from(_ raw: String) -> AppAppearance {
        AppAppearance(rawValue: raw) ?? .system
    }
}
