import Foundation

// Dieses Struct matcht die JSON-Struktur, die die KI zurückliefert
struct FoodAnalysisResponse: Codable {
    let foodName: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}
