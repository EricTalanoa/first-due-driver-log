import Foundation

// Hours-of-service helpers: what each tap in the LD flow means, the filled-in 24-hour chart,
// and the federal limits for property-carrying drivers (49 CFR 395.3).
// Mirrors lib/hos.ts on the website so both apps read and write LD days the same way.

/// What a driver can say they are doing. Each one maps to a duty status line on the chart.
public enum Activity: String, CaseIterable, Identifiable, Sendable {
    case pretrip, drive, fuel, quickBreak, lunch, load, unload, work, riding, posttrip, off

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .pretrip: return "Pre-trip inspection"
        case .drive: return "Driving"
        case .fuel: return "Fuel stop"
        case .quickBreak: return "Quick break"
        case .lunch: return "Lunch (30 min)"
        case .load: return "Start loading"
        case .unload: return "Start unload"
        case .work: return "Other work"
        case .riding: return "Switch drivers"
        case .posttrip: return "Post-trip inspection"
        case .off: return "Off duty"
        }
    }

    public var status: Status {
        switch self {
        case .drive: return .driving
        case .quickBreak, .lunch, .off: return .offDuty
        default: return .onDuty
        }
    }

    /// Saved in the entry's note; also what the LD screen shows as "now".
    public var note: String {
        switch self {
        case .pretrip: return "Pre-trip inspection"
        case .drive: return "Driving"
        case .fuel: return "Fueling"
        case .quickBreak: return "Quick break"
        case .lunch: return "Lunch break"
        case .load: return "Loading"
        case .unload: return "Unloading"
        case .work: return "Other work"
        case .riding: return "Riding – co-driver driving"
        case .posttrip: return "Post-trip inspection"
        case .off: return "Off duty"
        }
    }

    /// Works out which activity an entry was, from its note (or its status for older entries).
    public static func of(_ e: Entry) -> Activity {
        let note = (e.note.components(separatedBy: " | ").first ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if let a = allCases.first(where: { $0.status == e.status && note.hasPrefix($0.note.lowercased()) }) { return a }
        if e.status == .driving { return .drive }
        if note.contains("unload") { return .unload }
        if note.contains("load") { return .load }
        if note.contains("pre-trip") { return .pretrip }
        if note.contains("post-trip") { return .posttrip }
        if note.contains("lunch") { return .lunch }
        return e.status == .offDuty || e.status == .sleeper ? .off : .work
    }
}

/// A step in the LD flow: an activity, or clocking out.
public enum Step: Hashable, Sendable {
    case act(Activity)
    case clockOut

    /// The button label, which reads differently depending on what the driver is doing now.
    public func label(now: Activity?) -> String {
        switch self {
        case .clockOut: return "Clock out"
        case .act(.pretrip): return "Clock in"
        case .act(.drive): return now == .riding ? "Take the wheel" : "Start driving"
        case .act(.posttrip): return now == .drive || now == .riding ? "Arrive · post-trip" : "Post-trip inspection"
        case .act(.work): return now == .drive ? "Stop · other work" : "Back to work"
        case .act(let a): return a.label
        }
    }
}

/// The choices to offer next, given what the driver is doing now. `nil` = off the clock.
public func nextSteps(_ now: Activity?) -> [Step] {
    guard let now else { return [.act(.pretrip)] }
    switch now {
    case .drive: return ([.fuel, .quickBreak, .lunch, .unload, .load, .riding, .posttrip, .work] as [Activity]).map { Step.act($0) }
    case .riding: return ([.drive, .fuel, .quickBreak, .lunch, .unload, .load, .posttrip] as [Activity]).map { Step.act($0) }
    case .posttrip: return [.clockOut, .act(.drive), .act(.work)]
    case .quickBreak, .lunch, .off: return [.act(.drive), .act(.work), .act(.unload), .act(.posttrip), .clockOut]
    default: return [.act(.drive), .act(.quickBreak), .act(.lunch), .act(.posttrip), .clockOut]
    }
}

public enum Places {
    public static let preston = Office.preston.label
    static let hotelPrefix = "Hotel – "
    /// Marks the first entry of a day logged on the LD tab, so History can group LD days.
    public static let ldMark = " | LD trip"

    public static func hotel(_ city: String) -> String { city.hasPrefix(hotelPrefix) ? city : hotelPrefix + city }

    /// The city behind a place label: an office, "Hotel – Spokane, WA", or a typed address.
    public static func city(of place: String) -> Place? {
        if let o = Office.allCases.first(where: { $0.label == place }) { return o.point }
        return Cities.find(place.hasPrefix(hotelPrefix) ? String(place.dropFirst(hotelPrefix.count)) : place)
    }

    /// Estimated road miles between two places, or nil if either city is unknown.
    public static func estimateMiles(_ from: String, _ to: String) -> Double? {
        guard let a = city(of: from), let b = city(of: to) else { return nil }
        return (roadMiles(a, b) * 10).rounded() / 10
    }

    /// "Preston office" for the office's long label; everything else as typed.
    public static func short(_ place: String) -> String { place == preston ? "Preston office" : place }
}

/// Whether a day was long distance: logged on the LD tab or with the LD estimate, a hotel stop,
/// or a place more than 150 air-miles from the Preston office (the short-haul limit).
public func isLdDay(_ es: [Entry]) -> Bool {
    let home = Office.preston.point
    func far(_ p: String) -> Bool {
        guard !p.isEmpty, let c = Places.city(of: p) else { return false }
        return straightMiles(c.lat, c.lon, home.lat, home.lon) > 150
    }
    return es.contains { e in
        e.note.range(of: #"\bLD\b"#, options: .regularExpression) != nil
            || [e.from, e.to].contains { $0.hasPrefix(Places.hotelPrefix) || far($0) }
    }
}

// MARK: Timeline: the day as a list of status changes, for filling in or fixing a day

public struct TimelineStep: Identifiable, Equatable, Sendable {
    public var id: String
    public var time: Date
    public var step: Step
    public var place: String
    public var miles: Double?

    public init(id: String = UUID().uuidString.lowercased(), time: Date, step: Step, place: String, miles: Double? = nil) {
        self.id = id; self.time = time; self.step = step; self.place = place; self.miles = miles
    }
}

/// Reads a day's entries as status changes. Gaps between entries become Quick break steps.
public func toSteps(_ entries: [Entry]) -> [TimelineStep] {
    let es = entries.sorted { $0.start < $1.start }
    var out: [TimelineStep] = []
    for (i, e) in es.enumerated() {
        let a = Activity.of(e)
        out.append(TimelineStep(id: e.id, time: e.start, step: .act(a), place: e.from, miles: a == .drive ? e.miles : nil))
        let next = i + 1 < es.count ? es[i + 1] : nil
        if let end = e.end, next == nil || next!.start > end {
            out.append(TimelineStep(time: end, step: next == nil ? .clockOut : .act(.quickBreak), place: e.to.isEmpty ? e.from : e.to))
        }
    }
    return out
}

/// Turns status changes back into entries. Each step runs until the next one; the last must be Clock out.
public func toEntries(_ steps: [TimelineStep], tag: String = "") throws -> [Entry] {
    guard !steps.isEmpty else { throw LogError("Add your clock-in first.") }
    guard steps.last?.step == .clockOut else { throw LogError("End the day with Clock out.") }
    for i in steps.indices.dropFirst() where steps[i].time <= steps[i - 1].time {
        throw LogError("Step \(i + 1) must be after step \(i). Check the times.")
    }
    var out: [Entry] = []
    for i in steps.indices.dropLast() {
        let s = steps[i], n = steps[i + 1]
        guard case .act(let a) = s.step else { continue }
        let drive = a == .drive
        let from = s.place.trimmingCharacters(in: .whitespaces), to = n.place.trimmingCharacters(in: .whitespaces)
        out.append(Entry(id: s.id, status: a.status, start: s.time, end: n.time, from: from, to: drive ? to : "",
                         miles: drive ? s.miles ?? Places.estimateMiles(s.place, n.place) : nil, note: a.note))
    }
    if !tag.isEmpty, !out.isEmpty, !out[0].note.contains(tag) { out[0].note += tag }
    return out
}

extension Clock {
    /// "HH:mm" on `day`; a time not after `after` rolls onto the next day (past midnight).
    public func stepTime(day: String, _ hhmm: String, after: Date? = nil) throws -> Date {
        var t = try date(day: day, time: hhmm)
        var d = day
        while let after, t <= after {
            d = Clock.shift(d, by: 1)
            t = try date(day: d, time: hhmm)
        }
        return t
    }
}

// MARK: The 24-hour chart

public struct Segment: Equatable, Sendable {
    public let status: Status
    public let start: Date
    public let end: Date
    /// No entry here: shown as off duty, as on a paper log.
    public let filled: Bool
    public let entry: Entry?
}

public struct Chart: Sendable {
    public let segments: [Segment]
    public let start: Date
    public let end: Date
    /// Where the line stops: midnight for past days, now for today.
    public let upto: Date

    public var totals: [Status: TimeInterval] {
        segments.reduce(into: [:]) { $0[$1.status, default: 0] += $1.end.timeIntervalSince($1.start) }
    }

    /// Every recorded change of duty status, for the remarks.
    public var remarks: [Segment] { segments.filter { $0.entry.map { $0.start >= start } ?? false } }

    /// The entry that ended the day, if the driver has clocked out.
    public var clockOut: Entry? {
        guard let last = segments.last(where: { $0.entry != nil })?.entry, let end = last.end, end <= upto, end < self.end else { return nil }
        return last
    }

    /// The day's line, midnight to midnight (or to `now` for today). Time with no entry is Off duty:
    /// before clock-in, after clock-out and between entries.
    public init(entries: [Entry], day: String, clock: Clock, now: Date) {
        let (start, end) = clock.bounds(day)
        let upto = min(end, max(start, now))
        let rows = entries.filter { $0.start < upto && ($0.end ?? now) > start }.sorted { $0.start < $1.start }
        var segs: [Segment] = []
        var t = start
        for e in rows {
            let s = max(start, e.start), f = min(upto, e.end ?? now)
            if s > t { segs.append(Segment(status: .offDuty, start: t, end: s, filled: true, entry: nil)) }
            if f > max(s, t) { segs.append(Segment(status: e.status, start: max(s, t), end: f, filled: false, entry: e)) }
            t = max(t, f)
        }
        if upto > t { segs.append(Segment(status: .offDuty, start: t, end: upto, filled: true, entry: nil)) }
        self.segments = segs
        self.start = start
        self.end = end
        self.upto = upto
    }
}

// MARK: Hours-of-service clocks

public struct HosClocks: Equatable, Sendable {
    /// Seconds left (negative when over).
    public let drive: TimeInterval
    public let window: TimeInterval
    public let breakDue: TimeInterval
    public let cycle: TimeInterval
    public let shiftStart: Date?

    /// Time left under each limit right now: 11 hours driving and a 14-hour window after 10 hours off,
    /// a 30-minute break after 8 hours of driving, and 70 hours on duty in 8 days (reset by 34 hours off).
    /// Time with no entry counts as off duty.
    public init(entries: [Entry], now: Date) {
        let h: TimeInterval = 3600
        let recent = entries.filter { $0.start < now && ($0.end ?? now) > now.addingTimeInterval(-10 * 24 * h) }
            .map { e -> Entry in var e = e; e.end = e.end ?? now; return e }
            .sorted { $0.start < $1.start }
        let work = recent.filter(\.isWork)
        var shift: Date?, cycleStart = now.addingTimeInterval(-8 * 24 * h), lastEnd = Date.distantPast
        for w in work {
            let gap = w.start.timeIntervalSince(lastEnd)
            if gap >= 10 * h { shift = w.start }
            if gap >= 34 * h { cycleStart = max(cycleStart, w.start) }
            lastEnd = max(lastEnd, w.end!)
        }
        if now.timeIntervalSince(lastEnd) >= 10 * h { shift = nil }
        func inRange(_ e: Entry, from: Date) -> TimeInterval { max(0, min(e.end!, now).timeIntervalSince(max(e.start, from))) }
        let driving = shift.map { s in work.filter { $0.status == .driving }.reduce(0) { $0 + inRange($1, from: s) } } ?? 0
        var sinceBreak: TimeInterval = 0, lastDrive = Date.distantPast
        for e in recent where e.status == .driving {
            if e.start.timeIntervalSince(lastDrive) >= 0.5 * h { sinceBreak = 0 }
            sinceBreak += e.end!.timeIntervalSince(e.start)
            lastDrive = e.end!
        }
        if now.timeIntervalSince(lastDrive) >= 0.5 * h { sinceBreak = 0 }
        shiftStart = shift
        drive = 11 * h - driving
        window = shift.map { 14 * h - now.timeIntervalSince($0) } ?? 14 * h
        breakDue = 8 * h - sinceBreak
        cycle = 70 * h - work.reduce(0) { $0 + inRange($1, from: cycleStart) }
    }
}
