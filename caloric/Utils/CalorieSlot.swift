//
//  CalorieSlot.swift
//  caloric
//

import Foundation

struct CalorieSlot: Identifiable {
    let id = UUID()
    let hour: Double
    let calories: Double
    let workoutKcal: Double
    let isSleep: Bool
    let isWorkout: Bool
    let isFuture: Bool
    var total: Double { calories + workoutKcal }
}
