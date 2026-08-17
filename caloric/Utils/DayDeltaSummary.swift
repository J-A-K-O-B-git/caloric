//
//  DayDeltaSummary.swift
//  caloric
//
//  Deterministic input for the day narrative.
//
//  The whole point of this type is that it decomposes *the number on screen*:
//  the "% vs. Gestern" figure in the KPI tile. Its component deltas add up
//  exactly to the difference behind that percentage, so the text explains what
//  the user is looking at rather than a second, similar-looking figure of its
//  own. Everything here is plain arithmetic — the model formulates, it never
//  calculates.
//

import Foundation

struct DayDeltaSummary: Codable, Equatable {

    struct ComponentDelta: Codable, Equatable {
        /// Stable identifier the prompt refers to: "bmr", "neat", "eat", …
        let key: String
        let todayKcal: Double
        let previousKcal: Double

        var deltaKcal: Double { todayKcal - previousKcal }

        /// Share of the whole day-over-day difference this component accounts
        /// for. Negative when it pushes against the overall direction.
        func shareOfTotalDelta(_ totalDelta: Double) -> Double? {
            guard abs(totalDelta) > 0.5 else { return nil }
            return deltaKcal / totalDelta * 100.0
        }

        private enum CodingKeys: String, CodingKey {
            case key, todayKcal, previousKcal
        }
    }

    /// Raw context so the model can name a *reason*, not just restate kcal.
    struct Context: Codable, Equatable {
        let steps: Int
        let stepsPrevious: Int
        let standMinutes: Double
        let standMinutesPrevious: Double
        let workoutMinutes: Double
        let workoutMinutesPrevious: Double
        let sleepHours: Double
        /// TEF comes from logged macros. Without this flag a day nobody logged
        /// looks identical to a day of eating nothing.
        let foodLoggedToday: Bool
        let foodLoggedPrevious: Bool
    }

    /// How the day sits against the last seven, and the raw material for an
    /// insight worth reading. Optional throughout: early on there is no week
    /// to compare against, and a narrative must still work without one.
    struct Weekly: Codable, Equatable {
        let averageKcal: Double
        let percentVsAverage: Double
        let averageSteps: Int
        let daysCounted: Int
    }

    /// Figures derived from the day that are interesting in their own right —
    /// the model may quote these, but it may not compute new ones.
    struct Highlights: Codable, Equatable {
        /// Share of the day's burn that came from moving at all.
        let activeSharePercent: Double
        /// EPOC still owed from today's sessions.
        let afterburnKcal: Double
        /// What a thousand steps are worth for this body.
        let kcalPerThousandSteps: Double
        /// Longest stretch of the day, in hours, spent awake so far.
        let wakingHours: Double
    }

    let dateKey: String
    /// Exactly the figure rendered in the KPI tile.
    let percentVsPreviousDay: Double
    let todayTotalKcal: Double
    let previousTotalKcal: Double
    /// True while the day is still running: today's NEAT and EAT only cover the
    /// hours so far, while the previous day is complete. Mid-day that alone
    /// explains most of a negative percentage, and saying so is the honest
    /// reading of the number.
    let isPartialDay: Bool
    let elapsedFractionOfWakingDay: Double
    let components: [ComponentDelta]
    let neatBreakdown: [ComponentDelta]
    /// Whether the day's BMR actually changed for a reason (illness, cycle).
    let bmrFactorsChanged: Bool
    let context: Context
    let weekly: Weekly?
    let highlights: Highlights?
    /// The user's own target for the day, if they set one. Nil means there is
    /// no goal and the text must not invent a target to measure against.
    let goalKcal: Double?

    var totalDeltaKcal: Double { todayTotalKcal - previousTotalKcal }

    /// Component that accounts for most of the difference.
    ///
    /// BMR is excluded unless one of its factors actually changed: it is by far
    /// the largest component, so on absolute kcal it would win nearly every
    /// comparison and crowd out the part of the day the user influenced.
    var dominantComponent: ComponentDelta? {
        let candidates = bmrFactorsChanged
            ? components
            : components.filter { $0.key != "bmr" }
        return candidates.max { abs($0.deltaKcal) < abs($1.deltaKcal) }
    }

    // MARK: - Prompt payload

    /// Compact, rounded JSON. Rounding keeps the model from echoing a precision
    /// the underlying estimates do not have.
    func promptJSON() -> String {
        func round0(_ v: Double) -> Int { Int(v.rounded()) }

        func componentDict(_ c: ComponentDelta) -> [String: Any] {
            var d: [String: Any] = [
                "key": c.key,
                "today": round0(c.todayKcal),
                "previousDay": round0(c.previousKcal),
                "delta": round0(c.deltaKcal)
            ]
            if let share = c.shareOfTotalDelta(totalDeltaKcal) {
                d["shareOfTotalDeltaPercent"] = round0(share)
            }
            return d
        }

        var payload: [String: Any] = [
            "percentToExplain": round0(percentVsPreviousDay),
            "todayTotal": round0(todayTotalKcal),
            "previousDayTotal": round0(previousTotalKcal),
            "totalDelta": round0(totalDeltaKcal),
            "isPartialDay": isPartialDay,
            "elapsedPercentOfWakingDay": round0(elapsedFractionOfWakingDay * 100),
            "components": components.map(componentDict),
            "neatBreakdown": neatBreakdown.map(componentDict),
            "bmrFactorsChanged": bmrFactorsChanged,
            "context": [
                "steps": context.steps,
                "stepsPreviousDay": context.stepsPrevious,
                "standMinutes": round0(context.standMinutes),
                "standMinutesPreviousDay": round0(context.standMinutesPrevious),
                "workoutMinutes": round0(context.workoutMinutes),
                "workoutMinutesPreviousDay": round0(context.workoutMinutesPrevious),
                "sleepHours": context.sleepHours,
                "foodLoggedToday": context.foodLoggedToday,
                "foodLoggedPreviousDay": context.foodLoggedPrevious
            ]
        ]

        if let weekly {
            payload["weekly"] = [
                "averageKcal": round0(weekly.averageKcal),
                "percentVsAverage": round0(weekly.percentVsAverage),
                "averageSteps": weekly.averageSteps,
                "daysCounted": weekly.daysCounted
            ]
        }
        if let h = highlights {
            payload["highlights"] = [
                "activeSharePercent": round0(h.activeSharePercent),
                "afterburnKcal": round0(h.afterburnKcal),
                "kcalPerThousandSteps": round0(h.kcalPerThousandSteps),
                "wakingHours": (h.wakingHours * 10).rounded() / 10
            ]
        }

        // The gap is computed here for the same reason every other figure is:
        // the model may quote numbers, never derive them — and "how much is
        // left" is a subtraction it would otherwise have to do itself.
        if let goalKcal, goalKcal > 0 {
            payload["goal"] = [
                "targetKcal": round0(goalKcal),
                "reachedPercent": round0(todayTotalKcal / goalKcal * 100),
                "remainingKcal": round0(max(0, goalKcal - todayTotalKcal))
            ]
        }

        // Named here rather than left to the model: picking the main driver is a
        // ranking decision, and ranking is arithmetic.
        if let dominant = dominantComponent {
            payload["leadWith"] = dominant.key
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload,
                                                     options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    /// Identity of the *numbers*, not of the day. A cached narrative stays valid
    /// until the values move by more than a 10 kcal bucket, which is what makes
    /// caching on a still-running day safe.
    ///
    /// Built by hand rather than with `Hasher`: that one is seeded per process,
    /// so its values differ between launches and no cache entry would ever match
    /// again after a restart.
    var fingerprint: String {
        func bucket(_ v: Double) -> Int { Int((v / 10.0).rounded()) }

        var parts: [String] = [dateKey, String(bucket(todayTotalKcal)),
                               String(bucket(previousTotalKcal))]
        for c in components + neatBreakdown {
            parts.append("\(c.key):\(bucket(c.todayKcal)):\(bucket(c.previousKcal))")
        }
        return parts.joined(separator: "|")
    }
}
