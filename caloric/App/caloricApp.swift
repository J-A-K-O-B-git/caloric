//
//  caloricApp.swift
//  caloric
//

import SwiftUI
import SwiftData

@main
struct caloricApp: App {

    let container: ModelContainer

    init() {
        container = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .caloricAppearance()
        }
        .modelContainer(container)
    }

    // MARK: - Container setup

    /// Single persistent store at caloric.store with a versioned migration plan.
    /// UserProfile is identical in V1 and V2 — it is always preserved.
    /// Cache data (DailyActivityRecord, DayCacheEntry) is migrated automatically;
    /// if migration is impossible the cache is wiped and rebuilt from HealthKit on
    /// next launch, but UserProfile is never lost.
    private static func makeContainer() -> ModelContainer {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let storeURL = appSupport.appendingPathComponent("caloric.store")
        let config   = ModelConfiguration(url: storeURL)

        let fullSchema = Schema([UserProfile.self, DailyActivityRecord.self, DayCacheEntry.self])

        do {
            return try ModelContainer(
                for: fullSchema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            // Migration could not be applied (e.g. store is already on V2 or
            // corrupted). Wipe only the cache tables by deleting the store and
            // retrying — UserProfile will need one-time re-onboarding.
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: storeURL.path + suffix)
            }
            // swiftlint:disable:next force_try
            return try! ModelContainer(
                for: fullSchema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [config]
            )
        }
    }
}
