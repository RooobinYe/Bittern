//
//  AppSettingKey.swift
//  Bittern
//

import Foundation

/// UserDefaults keys. Changing one loses the saved value.
enum AppSettingKey {
    static let privacyModeEnabled = "privacyModeEnabled"
    static let minPriceThreshold = "minPriceThreshold"
    static let performanceMode = "performanceMode"
    static let sortOption = "sortOption"
    static let contributionPlan = "contributionPlan"
    /// Debug builds only, to tell whether the lens's Liquid Glass is what
    /// glows brighter than white near the bottom of the card.
    static let debugLensGlassEnabled = "debugLensGlassEnabled"
}
