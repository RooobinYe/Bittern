//
//  ShareSheet.swift
//  Bittern
//

import SwiftUI
import UIKit
import OSLog

/// A standard UIActivityViewController wrapper for sharing items.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let colorScheme: ColorScheme

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        controller.overrideUserInterfaceStyle = colorScheme.userInterfaceStyle

        // When sharing a single image, suggest saving to photos as well.
        if items.count == 1, items.first is UIImage {
            controller.excludedActivityTypes = nil
        }

        controller.completionWithItemsHandler = { _, completed, _, error in
            if let error {
                AppLog.sharing.error("Share failed: \(AppLog.describe(error))")
            }

            if completed {
                AppLog.sharing.debug("Share completed successfully")
            }
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        uiViewController.overrideUserInterfaceStyle = colorScheme.userInterfaceStyle
    }
}

private extension ColorScheme {
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .dark:
            .dark
        default:
            .light
        }
    }
}
