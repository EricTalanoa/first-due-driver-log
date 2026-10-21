import Foundation

// Plans a whole work day from a few answers: office → each job's load and unload cities → office.
// Distances are straight-line estimates scaled for roads; there is no live routing.
// Mirrors lib/simple-day.ts on the website so both plan days the same way.

public struct Place: Equatable, Sendable {
    public let name: String
    public let lat: Double
    public let lon: Double
}

public enum Office: String, CaseIterable, Codable, Identifiable, Sendable {
    case preston = "Preston"
    case kent = "Kent"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .preston: return "Preston office – 8126 304th Ave SE, Preston, WA 98050"
        case .kent: return "Kent office – 21854 76th Ave S, Kent, WA 98032"
        }
    }

    public var point: Place {
        switch self {
        case .preston: return Place(name: "Preston office", lat: 47.5235, lon: -121.929)
        case .kent: return Place(name: "Kent office", lat: 47.4005, lon: -122.2405)
        }
    }
}

private let raw = "Seattle 47.6062 -122.3321|Ballard 47.6687 -122.3843|West Seattle 47.5667 -122.3868|Queen Anne 47.6374 -122.3571|Capitol Hill 47.6253 -122.3222|Fremont 47.651 -122.35|Greenwood 47.6907 -122.3553|Northgate 47.7062 -122.3255|Lake City 47.7193 -122.295|University District 47.6614 -122.3133|Georgetown 47.5487 -122.3214|Rainier Beach 47.5126 -122.267|Bellevue 47.6101 -122.2015|Factoria 47.5779 -122.1696|Totem Lake 47.7134 -122.1857|Redmond 47.674 -122.1215|Kirkland 47.6769 -122.206|Bothell 47.7601 -122.2054|Woodinville 47.7543 -122.1635|Issaquah 47.5301 -122.0326|Sammamish 47.6163 -122.0356|Preston 47.5215 -121.9318|Fall City 47.5673 -121.8887|Snoqualmie 47.5287 -121.8254|North Bend 47.4957 -121.7868|Carnation 47.6479 -121.914|Duvall 47.7423 -121.9857|Monroe 47.8554 -121.9709|Sultan 47.8626 -121.8165|Gold Bar 47.8568 -121.697|Snohomish 47.9129 -122.0982|Mill Creek 47.8601 -122.2043|Lynnwood 47.8209 -122.3151|Edmonds 47.8107 -122.3774|Mountlake Terrace 47.7882 -122.3087|Brier 47.7845 -122.274|Shoreline 47.7557 -122.3415|Lake Forest Park 47.7568 -122.2807|Kenmore 47.7573 -122.244|Mukilteo 47.9445 -122.3046|Everett 47.979 -122.2021|Marysville 48.0518 -122.1771|Lake Stevens 48.0151 -122.064|Granite Falls 48.084 -121.9687|Arlington 48.1987 -122.1251|Stanwood 48.2412 -122.3707|Mount Vernon 48.4212 -122.3341|Burlington 48.4757 -122.3254|Anacortes 48.5126 -122.6127|Oak Harbor 48.2932 -122.6432|Bellingham 48.7519 -122.4787|Ferndale 48.8465 -122.591|Lynden 48.9465 -122.4521|Blaine 48.9937 -122.7471|Renton 47.4829 -122.2171|Newcastle 47.5301 -122.1557|Mercer Island 47.5707 -122.2221|Medina 47.6204 -122.2279|Tukwila 47.474 -122.261|SeaTac 47.4436 -122.2961|Burien 47.4704 -122.3468|Normandy Park 47.4362 -122.3407|Des Moines 47.4018 -122.3243|Kent 47.3809 -122.2348|Covington 47.3582 -122.1224|Maple Valley 47.3926 -122.0465|Hobart 47.4229 -121.969|Ravensdale 47.3526 -121.9837|Black Diamond 47.3087 -122.0032|Enumclaw 47.2043 -121.9915|Auburn 47.3073 -122.2285|Federal Way 47.3223 -122.3126|Algona 47.2793 -122.2507|Pacific 47.2643 -122.2501|Edgewood 47.2501 -122.2937|Sumner 47.2032 -122.2404|Bonney Lake 47.1771 -122.1868|Buckley 47.1632 -122.0268|Puyallup 47.1854 -122.2929|Fife 47.2393 -122.3571|Milton 47.2482 -122.3132|Tacoma 47.2529 -122.4443|University Place 47.2357 -122.5501|Steilacoom 47.1698 -122.6029|Lakewood 47.1718 -122.5185|Gig Harbor 47.3293 -122.5801|Spanaway 47.104 -122.4346|Graham 47.0529 -122.2943|Orting 47.0979 -122.2043|DuPont 47.0971 -122.6315|Olympia 47.0379 -122.9007|Lacey 47.0343 -122.8232|Tumwater 47.0073 -122.9093|Yelm 46.9421 -122.6059|Shelton 47.2151 -123.1007|Centralia 46.7162 -122.9543|Chehalis 46.662 -122.964|Bremerton 47.5673 -122.6326|Silverdale 47.6446 -122.6949|Poulsbo 47.736 -122.6465|Port Orchard 47.5404 -122.6363|Bainbridge Island 47.6262 -122.5212|Kingston 47.7987 -122.4982|Vashon 47.4473 -122.4598|Port Townsend 48.117 -122.7604|Sequim 48.0795 -123.1018|Port Angeles 48.1181 -123.4307|Aberdeen 46.9754 -123.8157|Cle Elum 47.1954 -120.9392|Ellensburg 46.9965 -120.5478|Wenatchee 47.4235 -120.3103|Leavenworth 47.5962 -120.6615|Yakima 46.6021 -120.5059|Moses Lake 47.1301 -119.2781|Richland 46.2857 -119.2845|Kennewick 46.2112 -119.1372|Pasco 46.2396 -119.1006|Walla Walla 46.0646 -118.343|Spokane 47.6588 -117.426|Spokane Valley 47.6732 -117.2394|Longview 46.1382 -122.9382|Kelso 46.1468 -122.9084|Ridgefield 45.8151 -122.7426|Battle Ground 45.7807 -122.5334|Vancouver 45.6387 -122.6615|Camas 45.5871 -122.3995|Portland 45.5152 -122.6784|Gresham 45.4982 -122.4318|Beaverton 45.4871 -122.8037|Hillsboro 45.5229 -122.9898|Lake Oswego 45.4207 -122.6706|Hood River 45.7054 -121.5215|Salem 44.9429 -123.0351|Bend 44.0582 -121.3153|Eugene 44.0521 -123.0868"

public enum Cities {
    public static let all: [String: Place] = {
        var out: [String: Place] = [:]
        for row in raw.split(separator: "|") {
            var parts = row.split(separator: " ").map(String.init)
            guard parts.count >= 3, let lon = Double(parts.removeLast()), let lat = Double(parts.removeLast()) else { continue }
            let name = parts.joined(separator: " ")
            out[key(name)] = Place(name: name, lat: lat, lon: lon)
        }
        return out
    }()

    public static let names: [String] = all.values.map(\.name).sorted()

    static func key(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: ".", with: "")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Finds a city from free text like "issaquah", "Issaquah, WA" or "123 Main St, Kent, WA 98032".
    public static func find(_ input: String) -> Place? {
        let parts = input.split(separator: ",").map { part -> String in
            var p = String(part)
            p = p.replacingOccurrences(of: #"\b(wa|or|washington|oregon)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            p = p.replacingOccurrences(of: #"\d{5}(-\d{4})?"#, with: "", options: .regularExpression)
            return key(p)
        }.filter { !$0.isEmpty }
        for p in parts.reversed() { if let c = all[p] { return c } }
        let whole = key(input)
        let hits = all.keys.filter { $0.hasPrefix(whole) }
        return whole.count >= 3 && hits.count == 1 ? all[hits[0]] : nil
    }

    /// Closest known city to a GPS point, if one is within range.
    public static func nearest(lat: Double, lon: Double, within maxMiles: Double = 8) -> Place? {
        var best: Place?
        var dist = maxMiles
        for c in all.values {
            let m = straightMiles(lat, lon, c.lat, c.lon)
            if m < dist { best = c; dist = m }
        }
        return best
    }

    /// "Issaquah, WA"
    public static func label(_ c: Place) -> String {
        let oregon: Set<String> = ["Portland", "Gresham", "Beaverton", "Hillsboro", "Lake Oswego", "Hood River", "Salem", "Bend", "Eugene"]
        return "\(c.name), \(oregon.contains(c.name) ? "OR" : "WA")"
    }
}

/// Great-circle distance in miles.
public func straightMiles(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
    let r = Double.pi / 180
    let dl = (lat2 - lat1) * r, dn = (lon2 - lon1) * r
    let h = pow(sin(dl / 2), 2) + cos(lat1 * r) * cos(lat2 * r) * pow(sin(dn / 2), 2)
    return 3958.7613 * 2 * atan2(sqrt(h), sqrt(1 - h))
}

/// Road miles: straight line times a winding factor; at least half a mile for a same-city hop.
public func roadMiles(_ a: Place, _ b: Place) -> Double {
    let m = straightMiles(a.lat, a.lon, b.lat, b.lon)
    return max(0.5, m * (m > 60 ? 1.25 : 1.35))
}

/// Minutes behind the wheel for a leg: slower average speeds on short local hops.
public func driveMinutes(_ mi: Double) -> Int {
    let mph: Double = mi < 3 ? 22 : mi < 12 ? 30 : mi < 40 ? 40 : 52
    return Int((mi / mph * 60).rounded()) + 3
}

public struct Job: Equatable, Codable, Sendable {
    public var load: String
    public var unload: String
    public init(load: String = "", unload: String = "") { self.load = load; self.unload = unload }
}

public struct SimpleDay: Equatable, Sendable {
    public var date: String
    public var office: Office
    public var jobs: [Job]
    public var clockIn: String
    public var clockOut: String
    public var lunch: Int
    public var miles: Double?

    public init(date: String, office: Office = .preston, jobs: [Job] = [Job()], clockIn: String = "07:45", clockOut: String = "16:00", lunch: Int = 30, miles: Double? = nil) {
        self.date = date
        self.office = office
        self.jobs = jobs
        self.clockIn = clockIn
        self.clockOut = clockOut
        self.lunch = lunch
        self.miles = miles
    }
}

public struct Plan: Sendable {
    public let entries: [Entry]
    public let miles: Double
    public let driveMinutes: Int
    public let unknown: [String]
    public let route: [String]
}

private let simpleTag = "Simple day entry"

private func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }

/// Lays out a day: pre-trip, then for each job drive to load, load, drive to unload, unload;
/// drive back, post-trip. Lunch goes in whichever stop is nearest the middle of the shift.
public func planSimpleDay(_ d: SimpleDay, zone: TimeZone, newID: () -> String = { UUID().uuidString.lowercased() }) throws -> Plan {
    let clock = Clock(zone: zone)
    let jobs = d.jobs.map { Job(load: $0.load.trimmingCharacters(in: .whitespaces), unload: $0.unload.trimmingCharacters(in: .whitespaces)) }
        .filter { !$0.load.isEmpty || !$0.unload.isEmpty }
    if jobs.isEmpty || jobs.contains(where: { $0.load.isEmpty || $0.unload.isEmpty }) {
        throw LogError(d.jobs.count > 1 ? "Enter a load city and an unload city for each job." : "Enter both a load city and an unload city.")
    }
    struct Stop { let text: String; let city: Place?; let work: String; let drive: String }
    let tag = { (n: Int) in jobs.count > 1 ? " (job \(n))" : "" }
    var stops: [Stop] = []
    for (i, j) in jobs.enumerated() {
        stops.append(Stop(text: j.load, city: Cities.find(j.load), work: "Loading\(tag(i + 1))", drive: "To load\(tag(i + 1))"))
        stops.append(Stop(text: j.unload, city: Cities.find(j.unload), work: "Unloading\(tag(i + 1))", drive: "To unload\(tag(i + 1))"))
    }
    var unknown: [String] = []
    for s in stops where s.city == nil && !unknown.contains(s.text) { unknown.append(s.text) }

    let t0 = try clock.date(day: d.date, time: d.clockIn), t1 = try clock.date(day: d.date, time: d.clockOut)
    guard t1 > t0 else { throw LogError("Clock out must be after clock in.") }
    let span = Int((t1.timeIntervalSince(t0) / 60).rounded()), lunch = max(0, d.lunch)
    guard lunch < span else { throw LogError("Lunch is longer than the whole shift.") }

    let office = d.office.point
    var legs: [Double]
    let odometer = (d.miles ?? 0) > 0 ? d.miles! : nil
    if unknown.isEmpty {
        let points = [office] + stops.map { $0.city! } + [office]
        legs = (1..<points.count).map { roadMiles(points[$0 - 1], points[$0]) }
        if let total = odometer { let est = legs.reduce(0, +); legs = legs.map { $0 * total / est } }
    } else if let total = odometer {
        legs = Array(repeating: total / Double(stops.count + 1), count: stops.count + 1)
    } else {
        throw LogError("Couldn't find \(unknown.map { "“\($0)”" }.joined(separator: " or ")). Pick a city from the list, or enter the day's total miles.")
    }
    legs = legs.map(round1)
    // Rounding each leg can drift from the odometer total; settle the difference on the last leg.
    if let total = odometer { legs[legs.count - 1] = max(0, round1(total - legs.dropLast().reduce(0, +))) }

    let pre = 15, post = 10, minSite = 20
    var drive = legs.map(driveMinutes)
    let room = span - lunch - pre - post - stops.count * minSite
    guard room > 0 else { throw LogError("That shift is too short to fit the drives and stops. Use Advanced for this day.") }
    let driveTotal = drive.reduce(0, +)
    if driveTotal > room { drive = drive.map { max(4, Int((Double($0 * room) / Double(driveTotal)).rounded(.down))) } }
    let site = span - lunch - pre - post - drive.reduce(0, +)
    let atStop = stops.indices.map { site / stops.count + ($0 >= stops.count - site % stops.count ? 1 : 0) }

    // Lunch goes at the stop closest to the middle of the working time, the later one on a tie.
    let target = Int((Double(span - lunch) / 2).rounded())
    var lunchStop = -1, lunchAfter = 0, gap = Int.max
    var m = pre
    for i in stops.indices {
        m += drive[i]
        let into = min(max(target - m, 0), atStop[i]), off = abs(target - (m + into))
        if off <= gap { gap = off; lunchStop = i; lunchAfter = into }
        m += atStop[i]
    }

    let names = [d.office.label] + stops.map { $0.city.map(Cities.label) ?? $0.text }
    var entries: [Entry] = []
    var t = t0
    func add(_ status: Status, _ min: Int, _ from: String, _ to: String = "", _ miles: Double? = nil, _ note: String = "") {
        guard min > 0 else { return }
        let end = t.addingTimeInterval(TimeInterval(min * 60))
        entries.append(Entry(id: newID(), status: status, start: t, end: end, from: from, to: to, miles: miles, note: note))
        t = end
    }
    add(.onDuty, pre, names[0], "", nil, "Pre-trip inspection / prep at office")
    for (i, s) in stops.enumerated() {
        add(.driving, drive[i], names[i], names[i + 1], legs[i], s.drive)
        if lunch > 0 && lunchStop == i {
            add(.onDuty, lunchAfter, names[i + 1], "", nil, s.work)
            add(.offDuty, lunch, names[i + 1], "", nil, "Lunch break")
            add(.onDuty, atStop[i] - lunchAfter, names[i + 1], "", nil, s.work)
        } else {
            add(.onDuty, atStop[i], names[i + 1], "", nil, s.work)
        }
    }
    add(.driving, drive[stops.count], names[stops.count], names[0], legs[stops.count], "Return to office")
    add(.onDuty, Int((t1.timeIntervalSince(t) / 60).rounded()), names[0], "", nil, "Post-trip / unload equipment at office")
    entries[0].note += " | \(simpleTag): drive times and miles estimated from cities."
    let route = [d.office.rawValue] + stops.map { $0.city?.name ?? $0.text } + ["back"]
    return Plan(entries: entries, miles: round1(legs.reduce(0, +)), driveMinutes: drive.reduce(0, +), unknown: unknown, route: route)
}

/// Rebuilds the Simple day answers from entries it created earlier, so the day can be edited.
public func readSimpleDay(_ entries: [Entry], zone: TimeZone) -> SimpleDay? {
    let es = entries.sorted { $0.start < $1.start }
    guard let first = es.first, first.note.contains(simpleTag), !es.contains(where: { $0.end == nil }),
          let office = Office.allCases.first(where: { $0.label == first.from }) else { return nil }
    let city = { (s: String) in s.replacingOccurrences(of: #", (WA|OR)$"#, with: "", options: .regularExpression) }
    var jobs: [Job] = []
    for e in es where e.status == .driving {
        if e.note.hasPrefix("To load") { jobs.append(Job(load: city(e.to))) }
        else if e.note.hasPrefix("To unload"), !jobs.isEmpty { jobs[jobs.count - 1].unload = city(e.to) }
    }
    guard !jobs.isEmpty, !jobs.contains(where: { $0.unload.isEmpty }) else { return nil }
    let clock = Clock(zone: zone)
    let lunch = es.filter { $0.status == .offDuty && $0.note == "Lunch break" }.reduce(0.0) { $0 + $1.end!.timeIntervalSince($1.start) / 60 }
    var day = SimpleDay(date: clock.dayKey(first.start), office: office, jobs: jobs, clockIn: clock.hhmm(first.start), clockOut: clock.hhmm(es.last!.end!), lunch: Int(lunch.rounded()))
    // If the saved miles differ from the city estimate, the driver typed odometer miles; keep them.
    let saved = round1(es.reduce(0) { $0 + ($1.status == .driving ? $1.miles ?? 0 : 0) })
    if let plan = try? planSimpleDay(day, zone: zone, newID: { "" }) {
        if abs(plan.miles - saved) > 0.15 { day.miles = saved }
    } else {
        day.miles = saved
    }
    return day
}
