import Foundation

// MARK: - Food Analysis Models
//
// Matches the JSON schema requested from the AI in FoodAnalysisService.
// The analysis returns the individual recognised items rather than a single
// macro sum, so the user can verify and correct portions before anything is
// written into the journal — important for photos, where the model has to
// guess portion sizes.

struct FoodItem: Codable, Identifiable, Hashable {
    /// Local identity for SwiftUI lists; never part of the AI response.
    var id = UUID()
    var name: String
    var grams: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    var kcal: Double { protein * 4 + carbs * 4 + fat * 9 }

    private enum CodingKeys: String, CodingKey {
        case name, grams, protein, carbs, fat
    }
}

struct FoodAnalysisResponse: Codable {
    let items: [FoodItem]
}

extension Array where Element == FoodItem {
    var totalProtein: Double { reduce(0) { $0 + $1.protein } }
    var totalCarbs:   Double { reduce(0) { $0 + $1.carbs } }
    var totalFat:     Double { reduce(0) { $0 + $1.fat } }
    var totalKcal:    Double { reduce(0) { $0 + $1.kcal } }
}
