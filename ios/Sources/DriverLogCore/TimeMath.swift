import Foundation

/// Date helpers that always work in the driver's home-terminal time zone,
/// with days written as "yyyy-MM-dd" like the website.
public struct Clock: Sendable {
    public let zone: TimeZone

    public init(zone: TimeZone) { self.zone = zone }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }

    private func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = format
        return f
    }

    /// "2026-10-20" for the home-terminal day containing `date`.
    public func dayKey(_ date: Date) -> String { formatter("yyyy-MM-dd").string(from: date) }

    /// "2026-10-20T07:45", the website's local-input format.
    public func localInput(_ date: Date) -> String { formatter("yyyy-MM-dd'T'HH:mm").string(from: date) }

    /// "07:45"
    public func hhmm(_ date: Date) -> String { formatter("HH:mm").string(from: date) }

    /// The instant for a home-terminal wall time like "2026-10-20T07:45". Throws for times skipped by daylight saving.
    public func date(_ value: String) throws -> Date {
        let parts = value.split(whereSeparator: { $0 == "-" || $0 == "T" || $0 == ":" }).compactMap { Int($0) }
        guard parts.count == 5 else { throw LogError("Enter a valid date and time.") }
        let comps = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4])
        guard let d = calendar.date(from: comps), localInput(d) == value else {
            throw LogError("This time does not exist in your home-terminal timezone. Choose another time.")
        }
        return d
    }

    public func date(day: String, time: String) throws -> Date { try date("\(day)T\(time)") }

    /// Start and end of a home-terminal day. Not always 24 hours long.
    public func bounds(_ day: String) -> (start: Date, end: Date) {
        let start = (try? date(day: day, time: "00:00")) ?? Date()
        let end = (try? date(day: Clock.shift(day, by: 1), time: "00:00")) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    /// "7:45 AM"
    public func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = zone
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    /// Moves a "yyyy-MM-dd" day by whole days, independent of time zone.
    public static func shift(_ day: String, by n: Int) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = utc.timeZone
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: day), let moved = utc.date(byAdding: .day, value: n, to: d) else { return day }
        return f.string(from: moved)
    }

    /// Formats a "yyyy-MM-dd" day, e.g. "EEE, MMM d" → "Mon, Oct 19".
    public static func label(_ day: String, _ format: String) -> String {
        let parse = DateFormatter()
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.timeZone = TimeZone(identifier: "UTC")
        parse.dateFormat = "yyyy-MM-dd"
        guard let d = parse.date(from: day) else { return day }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US")
        out.timeZone = TimeZone(identifier: "UTC")
        out.dateFormat = format
        return out.string(from: d)
    }
}

/// "8h 05m"
public func duration(_ seconds: TimeInterval) -> String {
    let m = max(0, Int(seconds / 60))
    return "\(m / 60)h \(String(format: "%02d", m % 60))m"
}
