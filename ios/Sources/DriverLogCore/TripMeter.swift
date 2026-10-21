import Foundation

/// Turns a stream of GPS fixes into trip miles, using the same rules as the website:
/// - ignore movement smaller than the GPS wobble, so standing still adds nothing;
/// - measure from the last counted point, so slow traffic still adds up;
/// - drop single impossible jumps;
/// - bridge gaps (signal loss, app suspended) with the straight line plus a little for roads.
/// On a phone that keeps tracking in the background, gaps are rare; the bridging is a safety net.
public struct TripMeter: Codable, Equatable, Sendable {
    public var entryID: String
    public var start: Date
    public var miles: Double?
    public var partial: Bool
    public var from: String
    public var to: String
    public var anchor: Point?
    public var anchorAccuracy: Double
    public var lastFix: Date?
    public var glitches: Int
    public var fixes: Int

    public init(entry: Entry) {
        entryID = entry.id
        start = entry.start
        miles = entry.miles
        partial = entry.partial
        from = entry.from
        to = entry.to
        anchor = entry.lastPoint
        anchorAccuracy = 30
        lastFix = entry.lastPoint?.date
        glitches = 0
        fixes = 0
    }

    public enum Outcome: Equatable, Sendable { case ignoredWeak, ignoredGlitch, counted, held, bridged }

    /// Feeds one fix. `label` names the place (nearest city or coordinates).
    @discardableResult
    public mutating func take(lat: Double, lon: Double, accuracy: Double, time: Date, label: String) -> Outcome {
        guard accuracy >= 0, accuracy <= 100 else { return .ignoredWeak }
        let point = Point(lat: lat, lon: lon, time: time.timeIntervalSince1970 * 1000)
        if from.isEmpty { from = label }
        to = label
        var outcome = Outcome.held
        if let anchor {
            let span = time.timeIntervalSince(anchor.date)
            guard span > 0 else { return .held }
            let d = straightMiles(anchor.lat, anchor.lon, lat, lon)
            let mph = d / (span / 3600)
            let gap = lastFix.map { time.timeIntervalSince($0) } ?? span
            if gap > 60 {
                if mph <= 90 { miles = (miles ?? 0) + (d > 1 ? d * 1.2 : d) }
                if mph > 90 || gap > 300 { partial = true }
                self.anchor = point
                anchorAccuracy = accuracy
                outcome = .bridged
            } else if mph > 100 {
                glitches += 1
                guard glitches >= 3 else { return .ignoredGlitch }
                partial = true
                self.anchor = point
                anchorAccuracy = accuracy
            } else if d * 1609.34 > max(15, (anchorAccuracy + accuracy) / 2) {
                miles = (miles ?? 0) + d
                self.anchor = point
                anchorAccuracy = accuracy
                outcome = .counted
            }
        } else {
            if miles == nil { miles = 0 }
            // A first fix long after the drive started means the start of the trip was missed.
            partial = time.timeIntervalSince(start) > 60 || (miles ?? 0) > 0
            anchor = point
            anchorAccuracy = accuracy
            outcome = .counted
        }
        glitches = 0
        fixes += 1
        lastFix = max(lastFix ?? time, time)
        return outcome
    }

    /// The drive entry with the meter's results applied.
    public func apply(to entry: Entry, now: Date = Date()) -> Entry {
        var e = entry
        e.miles = miles
        e.from = from
        e.to = to
        e.lastPoint = anchor
        // Flag the distance if GPS went quiet for two minutes or never got a fix.
        e.partial = partial || anchor == nil || now.timeIntervalSince(lastFix ?? .distantPast) > 120
        return e
    }
}
