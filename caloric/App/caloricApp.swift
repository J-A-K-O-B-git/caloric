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
    ///
    /// Recovery ladder, worst case last:
    ///   1. Open with the migration plan (the normal path).
    ///   2. Open without it — covers a store that already matches the current
    ///      schema and only trips over the plan itself.
    ///   3. Rescue the UserProfile into memory, wipe the store, recreate it and
    ///      write the profile back.
    ///
    /// Step 3 deletes the whole store file, so the cache is always lost there.
    /// The profile survives whenever it could still be read — only an
    /// unreadable store costs the user their onboarding.
    private static func makeContainer() -> ModelContainer {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let storeURL = appSupport.appendingPathComponent("caloric.store")
        let config   = ModelConfiguration(url: storeURL)

        let fullSchema = Schema([UserProfile.self, DailyActivityRecord.self, DayCacheEntry.self])

        if let container = try? ModelContainer(
            for: fullSchema, migrationPlan: AppMigrationPlan.self, configurations: [config]
        ) {
            return container
        }

        if let container = try? ModelContainer(for: fullSchema, configurations: [config]) {
            return container
        }

        // Best effort: read the profile out before the store is destroyed.
        let rescued = rescueProfile(storeURL: storeURL)

        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: storeURL.path + suffix)
        }

        // swiftlint:disable:next force_try
        let container = try! ModelContainer(
            for: fullSchema, migrationPlan: AppMigrationPlan.self, configurations: [config]
        )

        if let rescued {
            let context = ModelContext(container)
            context.insert(rescued.makeProfile())
            try? context.save()
        }
        return container
    }

    /// Snapshot of the onboarding data, detached from the store it came from.
    private struct RescuedProfile {
        let name: String
        let birthDate: Date
        let geschlecht: String
        let weightText: String
        let weightUnit: String
        let heightText: String
        let heightUnit: String
        let bodyFatText: String
        let weissKfa: Bool
        let sprache: String
        let stoffwechselFaktor: Double
        let schlafStunden: Double
        let selectedConditions: [String]
        let isOnboardingCompleted: Bool

        func makeProfile() -> UserProfile {
            let p = UserProfile(
                name: name, birthDate: birthDate, geschlecht: geschlecht,
                weightText: weightText, weightUnit: weightUnit,
                heightText: heightText, heightUnit: heightUnit,
                bodyFatText: bodyFatText, weissKfa: weissKfa, sprache: sprache,
                stoffwechselFaktor: stoffwechselFaktor, schlafStunden: schlafStunden,
                selectedConditions: selectedConditions
            )
            p.isOnboardingCompleted = isOnboardingCompleted
            return p
        }
    }

    /// Tries to open the store with just the UserProfile entity. Anything that
    /// goes wrong here is expected — the caller falls back to a clean store.
    private static func rescueProfile(storeURL: URL) -> RescuedProfile? {
        guard let container = try? ModelContainer(
            for: Schema([UserProfile.self]),
            configurations: [ModelConfiguration(url: storeURL)]
        ) else { return nil }

        let context = ModelContext(container)
        let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        guard let p = profiles.first(where: { $0.isOnboardingCompleted }) ?? profiles.first else {
            return nil
        }

        return RescuedProfile(
            name: p.name, birthDate: p.birthDate, geschlecht: p.geschlecht,
            weightText: p.weightText, weightUnit: p.weightUnit,
            heightText: p.heightText, heightUnit: p.heightUnit,
            bodyFatText: p.bodyFatText, weissKfa: p.weissKfa, sprache: p.sprache,
            stoffwechselFaktor: p.stoffwechselFaktor, schlafStunden: p.schlafStunden,
            selectedConditions: p.selectedConditions,
            isOnboardingCompleted: p.isOnboardingCompleted
        )
    }
}
