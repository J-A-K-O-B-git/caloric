//
//  DayDeltaSummary.swift
//  caloric
//
//  Deterministic input for the day narrative. Everything the language model is
//  allowed to talk about is computed here, in plain Swift, and handed over as
//  finished numbers — the model formulates, it never calculates.
//
//  Keeping this type free of any AI concern also makes it testable on its own.
//

import Foundation

struct DayDeltaSummary: Codable, Equatable {

    struct SegmentDelta: Codable, Equatable {
        /// Stable identifier the prompt refers to: "bmr", "neat", "eat", …
        let key: String
        let todayKcal: Double
        let yesterdayKcal: Double

        var deltaKcal: Double { todayKcal - yesterdayKcal }
        var deltaPercent: Double? {
            guard yesterdayKcal > 0 else { return nil }
            return (todayKcal - yesterdayKcal) / yesterdayKcal * 100.0
        }

        private enum CodingKeys: String, CodingKey {
            case key, todayKcal, yesterdayKcal
        }
    }

    /// Raw context so the model can name a *reason*, not just restate kcal.
    struct Context: Codable, Equatable {
        let steps: Int
        let stepsYesterday: Int
        let standMinutes: Double
        let standMinutesYesterday: Double
        let workoutMinutes: Double
        let workoutMinutesYesterday: Double
        let sleepHours: Double
        /// TEF comes from logged macros. Without this flag a day nobody logged
        /// looks identical to a day of eating nothing.
        let foodLoggedToday: Bool
        let foodLoggedYesterday: Bool
    }

    let dateKey: String
    /// True while the day is still running — the narrative must not present a
    /// partial day as a finished one.
    let isPartialDay: Bool
    /// Share of the waking day elapsed; yesterday's activity values are scaled
    /// by this so both sides describe the same slice of the day.
    let elapsedFraction: Double
    let totalTodayKcal: Double
    let totalYesterdayKcal: Double
    let segments: [SegmentDelta]
    let neatBreakdown: [SegmentDelta]
    /// Whether the day's BMR actually changed for a reason (illness, cycle).
    let bmrFactorsChanged: Bool
    let context: Context

    var totalDeltaKcal: Double { totalTodayKcal - totalYesterdayKcal }

    /// Largest absolute mover — the sentence the narrative should lead with.
    ///
    /// BMR is excluded unless one of its factors actually changed. It is by far
    /// the biggest segment (~1700 kcal against ~300 for NEAT), so on absolute
    /// kcal it wins almost every comparison, and a headline about a metabolism
    /// that did not move crowds out the part of the day the user influenced.
    var dominantSegment: SegmentDelta? {
        let candidates = bmrFactorsChanged
            ? segments
            : segments.filter { $0.key != "bmr" }
        return candidates.max { abs($0.deltaKcal) < abs($1.deltaKcal) }
    }

    // MARK: - Prompt payload

    /// Compact, rounded JSON. Rounding keeps the model from echoing a
    /// precision the underlying estimates do not have.
    func promptJSON() -> String {
        func round0(_ v: Double) -> Int { Int(v.rounded()) }

        func segmentDict(_ s: SegmentDelta) -> [String: Any] {
            var d: [String: Any] = [
                "key": s.key,
                "today": round0(s.todayKcal),
                "yesterday": round0(s.yesterdayKcal),
                "delta": round0(s.deltaKcal)
            ]
            if let pct = s.deltaPercent { d["deltaPercent"] = round0(pct) }
            return d
        }

        var payload: [String: Any] = [
            "isPartialDay": isPartialDay,
            "elapsedPercentOfWakingDay": round0(elapsedFraction * 100),
            "totalToday": round0(totalTodayKcal),
            "totalYesterday": round0(totalYesterdayKcal),
            "totalDelta": round0(totalDeltaKcal),
            "segments": segments.map(segmentDict),
            "neatBreakdown": neatBreakdown.map(segmentDict),
            "bmrFactorsChanged": bmrFactorsChanged,
            "context": [
                "steps": context.steps,
                "stepsYesterday": context.stepsYesterday,
                "standMinutes": round0(context.standMinutes),
                "standMinutesYesterday": round0(context.standMinutesYesterday),
                "workoutMinutes": round0(context.workoutMinutes),
                "workoutMinutesYesterday": round0(context.workoutMinutesYesterday),
                "sleepHours": context.sleepHours,
                "foodLoggedToday": context.foodLoggedToday,
                "foodLoggedYesterday": context.foodLoggedYesterday
            ]
        ]

        // Named here rather than left to the model: picking the driver is a
        // ranking decision, and ranking is arithmetic.
        if let dominant = dominantSegment {
            payload["leadWith"] = dominant.key
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload,
                                                     options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    /// Identity of the *numbers*, not of the day. A cached narrative stays
    /// valid until the values move by more than a 10 kcal bucket, which is what
    /// makes caching on a still-running day safe.
    ///
    /// Built by hand rather than with `Hasher`: that one is seeded per process,
    /// so its values differ between launches and no cache entry would ever
    /// match again after a restart.
    var fingerprint: String {
        func bucket(_ v: Double) -> Int { Int((v / 10.0).rounded()) }

        var parts: [String] = [dateKey, String(bucket(totalTodayKcal))]
        for s in segments + neatBreakdown {
            parts.append("\(s.key):\(bucket(s.todayKcal)):\(bucket(s.yesterdayKcal))")
        }
        return parts.joined(separator: "|")
    }
}
