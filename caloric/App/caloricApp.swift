//
//  caloricApp.swift
//  caloric
//

import SwiftUI
import SwiftData

@main
struct caloricApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(for: [UserProfile.self, DayCacheEntry.self])
    }
}
