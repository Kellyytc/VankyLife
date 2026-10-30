//
//  CalorieSnapApp.swift
//  CalorieSnap
//
//  Created by Kelly on 6/13/26.
//

import SwiftUI

@main
struct CalorieSnapApp: App {
    init() { ShopLocation.shared.resume() }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
