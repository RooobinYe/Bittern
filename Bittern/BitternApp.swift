//
//  BitternApp.swift
//  Bittern
//
//  Created by 叶桢荣 on 2026/6/6.
//

import SwiftUI
import UIKit

@main
struct BitternApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

extension UINavigationController {
    open override func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.isEnabled = true
        interactivePopGestureRecognizer?.delegate = nil
    }
}
