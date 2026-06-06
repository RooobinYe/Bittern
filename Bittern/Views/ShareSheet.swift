//
//  ShareSheet.swift
//  Bittern
//

import SwiftUI
import UIKit

/// A standard UIActivityViewController wrapper for sharing items.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )

        // When sharing a single image, suggest saving to photos as well.
        if items.count == 1, items.first is UIImage {
            controller.excludedActivityTypes = nil
        }

        controller.completionWithItemsHandler = { _, completed, _, error in
            if let error {
                print("[ShareSheet] Share failed: \(error.localizedDescription)")
            }

            if completed {
                print("[ShareSheet] Share completed successfully.")
            }
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
