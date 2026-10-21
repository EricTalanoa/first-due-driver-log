import Foundation

/// One line of the History page.
public struct DaySummary: Identifiable, Equatable, Sendable {
    public var id: String { day }
    public let day: String
    public let first: Date
    public let last: Date
    public let lunch: TimeInterval
    public let worked: TimeInterval
    public let miles: Double
    public let open: Bool
}

public struct MonthSummary: Identifiable, Equatable, Sendable {
    public var id: String { month }
    public let month: String
    public let worked: TimeInterval
    public let miles: Double
    public let days: [DaySummary]
}

/// Groups entries by the home-terminal day they start on, newest first, then by month.
public func history(_ log: Log, now: Date = Date()) -> [MonthSummary] {
    let clock = Clock(zone: log.profile.timeZone)
    let byDay = Dictionary(grouping: log.all) { clock.dayKey($0.start) }
    let days = byDay.keys.sorted(by: >).map { day -> DaySummary in
        let es = byDay[day]!.sorted { $0.start < $1.start }
        let work = es.filter(\.isWork)
        let span = work.isEmpty ? es : work
        let first = span[0].start
        let last = span.map { $0.end ?? now }.max()!
        let lunch = es.filter { $0.status == .offDuty && $0.start >= first && ($0.end ?? now) <= last }.reduce(0) { $0 + ($1.end ?? now).timeIntervalSince($1.start) }
        return DaySummary(day: day, first: first, last: last, lunch: lunch,
                          worked: work.reduce(0) { $0 + ($1.end ?? now).timeIntervalSince($1.start) },
                          miles: es.filter { $0.status == .driving }.reduce(0) { $0 + ($1.miles ?? 0) },
                          open: es.contains { $0.id == log.active?.id })
    }
    let byMonth = Dictionary(grouping: days) { String($0.day.prefix(7)) }
    return byMonth.keys.sorted(by: >).map { m in
        let ds = byMonth[m]!.sorted { $0.day > $1.day }
        return MonthSummary(month: m, worked: ds.reduce(0) { $0 + $1.worked }, miles: ds.reduce(0) { $0 + $1.miles }, days: ds)
    }
}

/// Entries that overlap a home-terminal day, oldest first, plus per-status totals clipped to the day.
public struct DayView: Sendable {
    public let rows: [Entry]
    public let totals: [Status: TimeInterval]
    public let miles: Double
    public let needsCheck: Bool

    public init(log: Log, day: String, now: Date = Date()) {
        let clock = Clock(zone: log.profile.timeZone)
        let (start, end) = clock.bounds(day)
        let all = log.entries + (log.active.map { [$0] } ?? [])
        rows = all.filter { $0.start < end && ($0.end ?? now) > start }.sorted { $0.start < $1.start }
        var t: [Status: TimeInterval] = [:]
        for e in rows { t[e.status, default: 0] += max(0, min(e.end ?? now, end).timeIntervalSince(max(e.start, start))) }
        totals = t
        let drives = log.entries.filter { $0.status == .driving && $0.end.map { clock.dayKey($0) == day } == true }
        miles = drives.reduce(0) { $0 + ($1.miles ?? 0) }
        needsCheck = drives.contains { $0.miles == nil || $0.partial }
    }
}

/// Entries that start on a home-terminal day (what "Clear day" and Simple day replace).
public func entriesStarting(on day: String, in log: Log) -> [Entry] {
    let (start, end) = Clock(zone: log.profile.timeZone).bounds(day)
    return log.entries.filter { $0.start >= start && $0.start < end }
}
