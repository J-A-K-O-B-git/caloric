//
//  ActivityCalculationService.swift
//  caloric
//
//  Converts raw HealthKit data into net NEAT and EAT calories.
//  All results are *net* — the resting BMR share for the same window is
//  subtracted to prevent double-counting against the base BMR ring.
//
//  NEAT math lives in NEATModel.swift (NEATCalculator / NEATInputs).
//  This service stays SYNCHRONOUS so it can be used from SwiftUI computed
//  properties. It maps already-fetched HealthKit aggregates into NEATInputs.
//

import Foundation
import HealthKit

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .americanFootball:             return "American Football"
        case .archery:                      return "Archery"
        case .australianFootball:           return "Australian Football"
        case .badminton:                    return "Badminton"
        case .baseball:                     return "Baseball"
        case .basketball:                   return "Basketball"
        case .bowling:                      return "Bowling"
        case .boxing:                       return "Boxing"
        case .climbing:                     return "Climbing"
        case .cricket:                      return "Cricket"
        case .crossTraining:                return "Cross Training"
        case .curling:                      return "Curling"
        case .cycling:                      return "Cycling"
        case .dance:                        return "Dance"
        case .elliptical:                   return "Elliptical"
        case .equestrianSports:             return "Equestrian Sports"
        case .fencing:                      return "Fencing"
        case .fishing:                      return "Fishing"
        case .functionalStrengthTraining:   return "Strength Training"
        case .golf:                         return "Golf"
        case .gymnastics:                   return "Gymnastics"
        case .handball:                     return "Handball"
        case .hiking:                       return "Hiking"
        case .hockey:                       return "Hockey"
        case .hunting:                      return "Hunting"
        case .lacrosse:                     return "Lacrosse"
        case .martialArts:                  return "Martial Arts"
        case .mindAndBody:                  return "Mind and Body"
        case .paddleSports:                 return "Paddle Sports"
        case .play:                         return "Play"
        case .preparationAndRecovery:       return "Preparation and Recovery"
        case .racquetball:                  return "Racquetball"
        case .rowing:                       return "Rowing"
        case .rugby:                        return "Rugby"
        case .running:                      return "Running"
        case .sailing:                      return "Sailing"
        case .skatingSports:                return "Skating Sports"
        case .snowSports:                   return "Snow Sports"
        case .soccer:                       return "Soccer"
        case .softball:                     return "Softball"
        case .squash:                       return "Squash"
        case .stairClimbing:                return "Stair Climbing"
        case .surfingSports:                return "Surfing Sports"
        case .swimming:                     return "Swimming"
        case .tableTennis:                  return "Table Tennis"
        case .tennis:                       return "Tennis"
        case .trackAndField:                return "Track and Field"
        case .traditionalStrengthTraining:  return "Traditional Strength Training"
        case .volleyball:                   return "Volleyball"
        case .walking:                      return "Walking"
        case .waterFitness:                 return "Water Fitness"
        case .waterPolo:                    return "Water Polo"
        case .waterSports:                  return "Water Sports"
        case .wrestling:                    return "Wrestling"
        case .yoga:                         return "Yoga"
        case .barre:                        return "Barre"
        case .coreTraining:                 return "Core Training"
        case .crossCountrySkiing:           return "Cross Country Skiing"
        case .downhillSkiing:               return "Downhill Skiing"
        case .flexibility:                  return "Flexibility"
        case .highIntensityIntervalTraining: return "HIIT"
        case .jumpRope:                     return "Jump Rope"
        case .kickboxing:                   return "Kickboxing"
        case .pilates:                      return "Pilates"
        case .snowboarding:                 return "Snowboarding"
        case .stairs:                       return "Stairs"
        case .stepTraining:                 return "Step Training"
        case .wheelchairWalkPace:           return "Wheelchair Walk"
        case .wheelchairRunPace:            return "Wheelchair Run"
        case .taiChi:                       return "Tai Chi"
        case .mixedCardio:                  return "Mixed Cardio"
        case .handCycling:                  return "Hand Cycling"
        case .discSports:                   return "Disc Sports"
        case .fitnessGaming:                return "Fitness Gaming"
        default:                            return "Workout"
        }
    }
}

struct ActivityCalculationService {

    // MARK: - Output

    struct WorkoutDetail: Identifiable {
        let id: UUID
        let name: String
        let kcal: Double
    }

    struct ActivityResult {
        let neatKcal: Double
        let eatKcal: Double
        let neatBreakdown: NEATBreakdown
        let workoutDetails: [WorkoutDetail]
        var totalActiveKcal: Double { neatKcal + eatKcal }

        init(neatKcal: Double, eatKcal: Double,
             neatBreakdown: NEATBreakdown = NEATBreakdown(neatSteps: 0, neatStand: 0, neatHR: 0),
             workoutDetails: [WorkoutDetail] = []) {
            self.neatKcal = neatKcal
            self.eatKcal = eatKcal
            self.neatBreakdown = neatBreakdown
            self.workoutDetails = workoutDetails
        }
    }

    // MARK: - EAT (Exercise Activity Thermogenesis)

    /// Net active calories from a single workout using the Hiilloskorpi HRR formula.
    /// Hiilloskorpi already measures net expenditure above rest — no extra BMR subtraction.
    /// VO2max fallback: 45 mL/kg·min (male) / 40 mL/kg·min (female).
    static func eat(
        workout: HKWorkoutSnapshot,
        weightKg: Double,
        vo2Max: Double?,
        hrRest: Double?,
        age: Int,
        isMale: Bool
    ) -> Double {
        guard let avgHR = workout.averageHeartRate,
              avgHR > 0, weightKg > 0 else { return 0 }

        let minutes = workout.duration / 60.0
        guard minutes > 0 else { return 0 }

        let vo2   = (vo2Max ?? 0) > 0 ? vo2Max! : (isMale ? 45.0 : 40.0)
        let hrRst = (hrRest ?? 0) > 0 ? hrRest! : 60.0
        let hrMax = 208.0 - 0.7 * Double(age)          // Tanaka — aligned with NEAT
        let hrr   = (avgHR - hrRst) / max(1, hrMax - hrRst)

        let kJperMin: Double = isMale
            ? weightKg * vo2 * (0.019  * hrr - 0.0043)
            : weightKg * vo2 * (0.0143 * hrr - 0.0038)
        var bruttoKcal = (kJperMin / 4.184) * minutes

        // EPOC — strength: fixed ×1.20. Others: linear 0–20 % between 60 % and 85 % HR_max.
        let isStrength = workout.activityType == .functionalStrengthTraining ||
                         workout.activityType == .traditionalStrengthTraining
        if isStrength {
            bruttoKcal *= 1.20
        } else {
            let intensity = hrMax > 0 ? avgHR / hrMax : 0
            if intensity >= 0.85 {
                bruttoKcal *= 1.20
            } else if intensity > 0.60 {
                bruttoKcal *= 1.0 + (intensity - 0.60) / (0.85 - 0.60) * 0.20
            }
        }

        return max(0, bruttoKcal)
    }

    // MARK: - Combined (synchronous)

    /// Pass the day you're computing via `referenceDate` (defaults to today) so past
    /// days use the full 24 h window instead of clamping to the current clock time.
    /// Pass `hrSegments` from `HKActivitySnapshot.hrSegments` for an HR-informed result;
    /// omit (default `[]`) when only aggregated data is available.
    struct ManualWorkoutData: Sendable {
        let id: UUID
        let name: String
        let kcal: Double
    }

    static func calculate(
        steps: Int,
        standTimeMinutes: Double,
        restingHR: Double?,
        hrSegments: [HRSegment] = [],
        vo2Max: Double?,
        workouts: [HKWorkoutSnapshot],
        manualWorkouts: [ManualWorkoutData] = [],
        weightKg: Double,
        age: Int,
        isMale: Bool,
        sleepHours: Double,
        bmrDynamisch: Double,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> ActivityResult {

        let workoutSeconds = workouts.reduce(0.0) { $0 + $1.duration }
        let workoutMin     = workoutSeconds / 60.0

        // Build workout windows for the reference day
        let dayStart = calendar.startOfDay(for: referenceDate)
        let isToday  = calendar.isDateInToday(referenceDate)
        let dayEnd   = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        let workoutWindows: [DateInterval] = workouts.map { DateInterval(start: $0.startDate, end: $0.endDate) }
            .compactMap { w in
                let s = max(w.start, dayStart)
                let e = min(w.end, isToday ? referenceDate : dayEnd)
                return e > s ? DateInterval(start: s, end: e) : nil
            }

        // Estimate the fraction of the counted day spent in workouts
        let countedStart = dayStart.addingTimeInterval((sleepHours > 0 ? sleepHours : 8.0) * 60 * 60)
        let countedEnd   = max(countedStart, isToday ? referenceDate : dayEnd)
        let countedWindow = DateInterval(start: countedStart, end: countedEnd)

        var overlapSeconds: Double = 0
        for w in workoutWindows {
            if let overlap = intersection(w, countedWindow) {
                overlapSeconds += overlap.duration
            }
        }
        let countedSeconds = max(1.0, countedWindow.duration)
        let workoutFractionOfCountedTime = min(1.0, max(0.0, overlapSeconds / countedSeconds))

        // Proportionally exclude workout-time steps from the total day steps.
        // This approximates removing steps that occurred during workouts when
        // per-minute step samples are not available in this layer.
        let nonWorkoutSteps = max(0, Int(round(Double(steps) * (1.0 - workoutFractionOfCountedTime))))

        // Recompute netStandMin using the same workout duration already derived above
        // (net stand = total stand − workout minutes)
        let netStandMin = max(0, standTimeMinutes - (overlapSeconds / 60.0))

        let dayEndMin = isToday ? referenceDate.timeIntervalSince(dayStart) / 60.0 : 1440.0
        let wakeMin   = (sleepHours > 0 ? sleepHours : 8.0) * 60.0

        let inputs = NEATInputs(
            nonWorkoutSteps:   nonWorkoutSteps,
            standTimeMinutes:  netStandMin,
            restingHR:         restingHR,
            workoutSeconds:    workoutSeconds,
            wakeMinuteOfDay:   wakeMin,
            dayEndMinuteOfDay: max(wakeMin, dayEndMin),
            hrSegments:        hrSegments,
            age:          age,
            isMale:       isMale,
            weightKg:     weightKg,
            bmrDynamisch: bmrDynamisch
        )

        let breakdown = NEATCalculator.neatDetailed(inputs)
        
        var details: [WorkoutDetail] = []
        
        // HealthKit Workouts
        for w in workouts {
            let kcal = eat(workout: w, weightKg: weightKg, vo2Max: vo2Max,
                           hrRest: restingHR, age: age, isMale: isMale)
            details.append(WorkoutDetail(id: w.id, name: w.activityType.name, kcal: kcal))
        }
        
        // Manual Workouts
        for mw in manualWorkouts {
            details.append(WorkoutDetail(id: mw.id, name: mw.name, kcal: mw.kcal))
        }
        
        let totalEatKcal = details.reduce(0) { $0 + $1.kcal }
        
        return ActivityResult(neatKcal: breakdown.total, eatKcal: totalEatKcal, neatBreakdown: breakdown, workoutDetails: details)
    }
}

private func intersection(_ a: DateInterval, _ b: DateInterval) -> DateInterval? {
    let s = max(a.start, b.start)
    let e = min(a.end, b.end)
    return e > s ? DateInterval(start: s, end: e) : nil
}
