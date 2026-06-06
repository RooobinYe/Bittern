//
//  AppSettings.swift
//  Bittern
//

import SwiftUI

enum AppSettingKey {
    static let appearanceMode = "appearanceMode"
    static let privacyModeEnabled = "privacyModeEnabled"
    static let minPriceThreshold = "minPriceThreshold"
    static let performanceMode = "performanceMode"
    static let sortOption = "sortOption"
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case automatic
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            "Auto"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .automatic:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}
