//
//  DateKey.swift
//  caloric
//
//  The "yyyy-MM-dd" key used to index days in JournalStore and the HealthKit
//  history cache. Previously each of them built its own DateFormatter; a single
//  formatter also avoids re-creating a comparatively expensive object.
//

import Foundation

enum DateKey {

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from key: String) -> Date? {
        formatter.date(from: key)
    }
}
