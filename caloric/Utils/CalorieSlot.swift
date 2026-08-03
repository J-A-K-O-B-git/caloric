//
//  CalorieSlot.swift
//  caloric
//
//  One half hour of the day, split into the three phases the charts draw:
//  asleep, awake, training. The split is by *phase*, not by energy model —
//  "awake" therefore carries the resting share for that half hour plus the
//  NEAT, digestion and caffeine burnt in it, because all of those happen
//  while awake and outside a workout.
//

import Foundation

struct CalorieSlot: Identifiable {
    let id = UUID()
    let hour: Double
    /// Resting share (BMR) for this half hour.
    let calories: Double
    /// Burnt awake and outside training: NEAT plus the digestion and
    /// caffeine bonuses. Zero while asleep and in the future.
    let activeKcal: Double
    let workoutKcal: Double
    let isSleep: Bool
    let isWorkout: Bool
    let isFuture: Bool

    var total: Double { calories + activeKcal + workoutKcal }

    // MARK: - Phase shares (chart segments)

    var sleepKcal: Double { isSleep ? calories : 0 }
    var awakeKcal: Double { isSleep ? activeKcal : calories + activeKcal }
}
