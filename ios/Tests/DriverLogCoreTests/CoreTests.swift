import XCTest
@testable import DriverLogCore

final class CoreTests: XCTestCase {
    let pacific = TimeZone(identifier: "America/Los_Angeles")!
    var clock: Clock { Clock(zone: pacific) }

    // MARK: Simple day (matches lib/simple-day.ts on the website)

    func testSingleJobMatchesWebsite() throws {
        var n = 0
        let plan = try planSimpleDay(SimpleDay(date: "2025-03-04", office: .preston, jobs: [Job(load: "Issaquah", unload: "Seattle")]), zone: pacific, newID: { n += 1; return "id\(n)" })
        XCTAssertEqual(plan.miles, 53.2)
        XCTAssertEqual(plan.entries.count, 8)
        XCTAssertEqual(plan.route, ["Preston", "Issaquah", "Seattle", "back"])
        XCTAssertEqual(clock.hhmm(plan.entries.first!.start), "07:45")
        XCTAssertEqual(clock.hhmm(plan.entries.last!.end!), "16:00")
        let lunch = plan.entries.first { $0.note == "Lunch break" }!
        XCTAssertEqual(clock.hhmm(lunch.start), "11:43")
        XCTAssertEqual(lunch.end!.timeIntervalSince(lunch.start), 30 * 60)
        try validate(Log(entries: plan.entries), now: plan.entries.last!.end!)
    }

    func testTwoJobsAndReadBack() throws {
        let day = SimpleDay(date: "2025-03-04", office: .kent, jobs: [Job(load: "Renton", unload: "Bellevue"), Job(load: "Kirkland, WA", unload: "Redmond")], clockOut: "17:30", lunch: 45)
        let plan = try planSimpleDay(day, zone: pacific)
        XCTAssertEqual(plan.miles, 57.8)
        XCTAssertEqual(plan.entries.count, 12)
        XCTAssertEqual(plan.entries.filter { $0.note.hasPrefix("To load (job 2)") }.count, 1)
        let back = readSimpleDay(plan.entries, zone: pacific)
        XCTAssertEqual(back?.jobs, [Job(load: "Renton", unload: "Bellevue"), Job(load: "Kirkland", unload: "Redmond")])
        XCTAssertEqual(back?.office, .kent)
        XCTAssertEqual(back?.clockOut, "17:30")
        XCTAssertEqual(back?.lunch, 45)
        XCTAssertNil(back?.miles)
    }

    func testOdometerMilesSaveExactly() throws {
        let plan = try planSimpleDay(SimpleDay(date: "2025-03-04", jobs: [Job(load: "Issaquah", unload: "Seattle")], miles: 80), zone: pacific)
        XCTAssertEqual(plan.miles, 80)
        XCTAssertEqual(readSimpleDay(plan.entries, zone: pacific)?.miles, 80)
    }

    func testUnknownCityNeedsMiles() {
        let day = SimpleDay(date: "2025-03-04", jobs: [Job(load: "Nowhereville", unload: "Seattle")])
        XCTAssertThrowsError(try planSimpleDay(day, zone: pacific))
        var withMiles = day
        withMiles.miles = 50
        XCTAssertEqual(try planSimpleDay(withMiles, zone: pacific).miles, 50)
    }

    func testFindCity() {
        XCTAssertEqual(Cities.find("123 Main St, Kent, WA 98032")?.name, "Kent")
        XCTAssertEqual(Cities.find("issaq")?.name, "Issaquah")
        XCTAssertEqual(Cities.nearest(lat: 47.535, lon: -122.04)?.name, "Issaquah")
        XCTAssertNil(Cities.nearest(lat: 46.0, lon: -121.0))
    }

    // MARK: Time

    func testDaylightSaving() {
        XCTAssertThrowsError(try clock.date("2026-03-08T02:30"))
        let (s, e) = clock.bounds("2026-03-08")
        XCTAssertEqual(e.timeIntervalSince(s), 23 * 3600)
        XCTAssertEqual(Clock.shift("2026-12-31", by: 1), "2027-01-01")
        XCTAssertEqual(Clock.label("2026-10-19", "EEE, MMM d"), "Mon, Oct 19")
        XCTAssertEqual(duration(8 * 3600 + 5 * 60 + 59), "8h 05m")
    }

    // MARK: GPS (same scripted drive as the website test: ~2.88 mi)

    func testTripMeter() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var m = TripMeter(entry: Entry.starting(.driving, at: base.addingTimeInterval(-10)))
        let lat = 47.53, step = 1.784e-4
        var lon = -122.10, t = base
        for _ in 0...60 { m.take(lat: lat, lon: lon, accuracy: 8, time: t, label: "x"); lon += step; t += 1 }
        lon -= step
        XCTAssertEqual(m.miles!, 0.5, accuracy: 0.03)
        for i in 0..<30 { t += 1; m.take(lat: lat + (i % 2 == 0 ? 5e-5 : -5e-5), lon: lon + (i % 3 == 0 ? 8e-5 : -8e-5), accuracy: 20, time: t, label: "x") }
        XCTAssertEqual(m.miles!, 0.5, accuracy: 0.03, "parked jitter adds nothing")
        t += 180; lon += step * 180
        XCTAssertEqual(m.take(lat: lat, lon: lon, accuracy: 8, time: t, label: "x"), .bridged)
        XCTAssertEqual(m.miles!, 2.3, accuracy: 0.05)
        XCTAssertFalse(m.partial, "a 3-minute gap is bridged without flagging")
        t += 1
        XCTAssertEqual(m.take(lat: lat, lon: lon + 0.1, accuracy: 8, time: t, label: "x"), .ignoredGlitch)
        for _ in 0..<10 { t += 1; lon += step; m.take(lat: lat, lon: lon, accuracy: 8, time: t, label: "x") }
        XCTAssertEqual(m.miles!, 2.38, accuracy: 0.05)
        XCTAssertEqual(m.take(lat: lat, lon: lon, accuracy: 150, time: t + 1, label: "x"), .ignoredWeak)
    }

    // MARK: Sync

    func testChangeSendsOnlyEdits() throws {
        let a = Entry(id: "a", status: .onDuty, start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 60))
        let b = Entry(id: "b", status: .driving, start: Date(timeIntervalSince1970: 60), end: Date(timeIntervalSince1970: 120), miles: 3)
        let prev = Log(entries: [a, b])
        var next = prev
        next.entries[1].miles = 4
        next.active = Entry.starting(.onDuty, at: Date(timeIntervalSince1970: 120))
        let c = change(from: prev, to: next)
        XCTAssertEqual(c.upserts.map(\.id).sorted(), ["b", next.active!.id].sorted())
        XCTAssertTrue(c.deletes.isEmpty)
        XCTAssertNil(c.profile)
        next.entries.removeFirst()
        XCTAssertEqual(change(from: prev, to: next).deletes, ["a"])
    }

    func testRowsRoundTrip() throws {
        XCTAssertNotNil(ISO.date("2026-10-21T04:32:39.275+00:00"))
        XCTAssertNotNil(ISO.date("2026-10-21 04:32:39.275+00"))
        let json = #"[{"id":"x","status":"Driving","start_at":"2026-10-19T16:00:00+00:00","end_at":null,"from_place":"","to_place":"","miles":3.5,"note":"","partial":true,"source":"gps","last_point":{"lat":47.5,"lon":-122.1,"time":1792000000000},"document":null,"shipper":null,"commodity":null}]"#
        let rows = try JSONDecoder().decode([EntryRow].self, from: Data(json.utf8))
        let log = makeLog(rows: rows, profile: nil)
        XCTAssertEqual(log.active?.status, .driving)
        XCTAssertEqual(log.active?.lastPoint?.lat, 47.5)
        XCTAssertEqual(log.profile.carrier, "First Due Movers")
        let encoded = try JSONEncoder().encode(Profile(coDriver: "Sam"))
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains("\"coDriver\":\"Sam\""))
    }

    func testValidateRejectsOverlap() {
        let a = Entry(status: .onDuty, start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 120))
        let b = Entry(status: .offDuty, start: Date(timeIntervalSince1970: 60), end: Date(timeIntervalSince1970: 90))
        XCTAssertThrowsError(try validate(Log(entries: [a, b])))
    }
}
