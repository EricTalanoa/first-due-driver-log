import Foundation

// Maps the in-memory log to the Supabase tables (see supabase/migrations) and back,
// and works out the smallest change to send to the save_log function.

/// A row of `public.entries`. Times are ISO 8601 strings so encoding never depends on a client's date strategy.
public struct EntryRow: Codable, Equatable, Sendable {
    public var id: String
    public var status: String
    public var start_at: String
    public var end_at: String?
    public var from_place: String
    public var to_place: String
    public var miles: Double?
    public var note: String
    public var partial: Bool
    public var source: String
    public var last_point: Point?
    public var document: String?
    public var shipper: String?
    public var commodity: String?
}

/// A row of `public.profiles`.
public struct ProfileRow: Codable, Equatable, Sendable {
    public var name: String
    public var carrier: String
    public var terminal: String
    public var office: String
    public var vehicle: String
    public var co_driver: String
    public var zone: String
}

public enum ISO {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let whole: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func string(_ d: Date) -> String { fractional.string(from: d) }

    public static func date(_ s: String) -> Date? {
        if let d = fractional.date(from: s) ?? whole.date(from: s) { return d }
        // Postgres can send "2026-10-21 04:32:39.275+00" style values.
        let fixed = s.replacingOccurrences(of: " ", with: "T").replacingOccurrences(of: #"([+-]\d\d)$"#, with: "$1:00", options: .regularExpression)
        return fractional.date(from: fixed) ?? whole.date(from: fixed)
    }
}

public extension Entry {
    var row: EntryRow {
        EntryRow(id: id, status: status.rawValue, start_at: ISO.string(start), end_at: end.map(ISO.string), from_place: from, to_place: to,
                 miles: miles, note: note, partial: partial, source: source.rawValue, last_point: lastPoint,
                 document: document, shipper: shipper, commodity: commodity)
    }

    init?(row r: EntryRow) {
        guard let status = Status(rawValue: r.status), let start = ISO.date(r.start_at) else { return nil }
        self.init(id: r.id, status: status, start: start, end: r.end_at.flatMap(ISO.date), from: r.from_place, to: r.to_place, miles: r.miles,
                  note: r.note, partial: r.partial, source: DistanceSource(rawValue: r.source) ?? .manual, lastPoint: r.last_point,
                  document: r.document, shipper: r.shipper, commodity: r.commodity)
    }
}

public extension Profile {
    init(row r: ProfileRow) {
        self.init(name: r.name, carrier: r.carrier, terminal: r.terminal, office: r.office, vehicle: r.vehicle, coDriver: r.co_driver, zone: r.zone)
    }
}

/// What changed between two versions of the log.
public struct LogChange: Equatable, Sendable {
    public var upserts: [EntryRow]
    public var deletes: [String]
    public var profile: Profile?

    public var isEmpty: Bool { upserts.isEmpty && deletes.isEmpty && profile == nil }
}

public func change(from prev: Log, to next: Log) -> LogChange {
    let before = Dictionary(prev.all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let after = next.all
    let ids = Set(after.map(\.id))
    return LogChange(
        upserts: after.filter { before[$0.id] != $0 }.map(\.row),
        deletes: before.keys.filter { !ids.contains($0) }.sorted(),
        profile: prev.profile == next.profile ? nil : next.profile
    )
}

/// Builds the log from loaded rows.
public func makeLog(rows: [EntryRow], profile: ProfileRow?) -> Log {
    var log = Log(profile: profile.map(Profile.init(row:)) ?? Profile())
    for e in rows.compactMap(Entry.init(row:)).sorted(by: { $0.start < $1.start }) {
        if e.end == nil { log.active = e } else { log.entries.append(e) }
    }
    return log
}
