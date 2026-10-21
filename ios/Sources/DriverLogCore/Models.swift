import Foundation

/// The four duty statuses, in the order the daily graph draws them.
public enum Status: String, Codable, CaseIterable, Identifiable, Sendable {
    case offDuty = "Off duty"
    case sleeper = "Sleeper berth"
    case driving = "Driving"
    case onDuty = "On duty"

    public var id: String { rawValue }
}

public enum DistanceSource: String, Codable, Sendable {
    case manual, gps
}

/// A GPS fix. `time` is epoch milliseconds, matching what the website stores.
public struct Point: Codable, Equatable, Sendable {
    public var lat: Double
    public var lon: Double
    public var time: Double

    public init(lat: Double, lon: Double, time: Double) {
        self.lat = lat
        self.lon = lon
        self.time = time
    }

    public var date: Date { Date(timeIntervalSince1970: time / 1000) }
}

/// One duty period. An entry with no `end` is the one being recorded now.
public struct Entry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var status: Status
    public var start: Date
    public var end: Date?
    public var from: String
    public var to: String
    public var miles: Double?
    public var note: String
    public var partial: Bool
    public var source: DistanceSource
    public var lastPoint: Point?
    public var document: String?
    public var shipper: String?
    public var commodity: String?

    public init(id: String = UUID().uuidString.lowercased(), status: Status, start: Date, end: Date? = nil, from: String = "", to: String = "",
                miles: Double? = nil, note: String = "", partial: Bool = false, source: DistanceSource = .manual, lastPoint: Point? = nil,
                document: String? = nil, shipper: String? = nil, commodity: String? = nil) {
        self.id = id
        self.status = status
        self.start = start
        self.end = end
        self.from = from
        self.to = to
        self.miles = miles
        self.note = note
        self.partial = partial
        self.source = source
        self.lastPoint = lastPoint
        self.document = document
        self.shipper = shipper
        self.commodity = commodity
    }

    /// A fresh period starting now (or at `start`). Drives are GPS-measured until edited.
    public static func starting(_ status: Status, at start: Date = Date()) -> Entry {
        Entry(status: status, start: start, partial: status == .driving, source: status == .driving ? .gps : .manual)
    }

    public var isWork: Bool { status == .onDuty || status == .driving }
}

public struct Profile: Codable, Equatable, Sendable {
    public var name: String
    public var carrier: String
    public var terminal: String
    public var office: String
    public var vehicle: String
    public var coDriver: String
    public var zone: String

    public init(name: String = "", carrier: String = "First Due Movers", terminal: String = "", office: String = "", vehicle: String = "",
                coDriver: String = "", zone: String = "America/Los_Angeles") {
        self.name = name
        self.carrier = carrier
        self.terminal = terminal
        self.office = office
        self.vehicle = vehicle
        self.coDriver = coDriver
        self.zone = zone
    }

    public var timeZone: TimeZone { TimeZone(identifier: zone) ?? TimeZone(identifier: "America/Los_Angeles")! }

    public static let zones = ["America/Los_Angeles", "America/Denver", "America/Phoenix", "America/Chicago", "America/New_York", "America/Anchorage", "Pacific/Honolulu"]
}

public struct Log: Equatable, Sendable {
    public var entries: [Entry]
    public var active: Entry?
    public var profile: Profile

    public init(entries: [Entry] = [], active: Entry? = nil, profile: Profile = Profile()) {
        self.entries = entries
        self.active = active
        self.profile = profile
    }

    /// Saved entries plus the one being recorded.
    public var all: [Entry] { entries + (active.map { [$0] } ?? []) }
}

public struct LogError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public func overlaps(_ a: Entry, _ b: Entry) -> Bool {
    a.start < (b.end ?? .distantFuture) && b.start < (a.end ?? .distantFuture)
}

/// The same checks the website and database apply before a save.
public func validate(_ log: Log, now: Date = Date()) throws {
    var ids = Set<String>()
    let slack = now.addingTimeInterval(60)
    for e in log.all {
        guard !e.id.isEmpty, e.id.count <= 100, !ids.contains(e.id), e.start <= slack else { throw LogError("Check the log entry and start time.") }
        ids.insert(e.id)
        if e.id == log.active?.id {
            guard e.end == nil else { throw LogError("End time must be after start time and not in the future.") }
        } else {
            guard let end = e.end, end > e.start, end <= slack else { throw LogError("End time must be after start time and not in the future.") }
        }
        if let m = e.miles, !(m.isFinite && m >= 0 && m <= 100_000) { throw LogError("Enter a valid distance.") }
        if e.from.count > 2000 || e.to.count > 2000 || e.note.count > 2000 { throw LogError("Text is too long.") }
    }
    let sorted = log.all.sorted { $0.start < $1.start }
    for i in sorted.indices.dropFirst() where overlaps(sorted[i - 1], sorted[i]) {
        throw LogError("Duty periods cannot overlap. Adjust the times first.")
    }
}
