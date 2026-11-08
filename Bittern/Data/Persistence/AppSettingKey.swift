//
//  AppSettingKey.swift
//  Bittern
//

import Foundation

/// UserDefaults keys. Changing one loses the saved value.
nonisolated enum AppSettingKey {
    static let privacyModeEnabled = "privacyModeEnabled"
    static let minPriceThreshold = "minPriceThreshold"
    static let performanceMode = "performanceMode"
    static let sortOption = "sortOption"
    static let contributionPlan = "contributionPlan"
    /// The host of the server market data comes through; absent for
    /// TradingView itself.
    static let marketDataServer = "marketDataServer"
}
