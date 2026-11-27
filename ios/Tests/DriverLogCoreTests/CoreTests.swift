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

    // MARK: LD day (matches planLdDay in lib/simple-day.ts)

    func testLdOfficeToHotelSplitsDriveForLunch() throws {
        let day = LdDay(date: "2025-03-04", start: LdPlace(at: .office, office: .preston), end: LdPlace(at: .hotel, hotel: "Spokane"))
        let plan = try planLdDay(day, zone: pacific)
        XCTAssertEqual(plan.miles, 262.5)
        XCTAssertEqual(plan.route, ["Preston", "Hotel (Spokane)"])
        XCTAssertEqual(plan.entries.map(\.status), [.onDuty, .driving, .offDuty, .driving, .onDuty])
        XCTAssertEqual(plan.entries[1].miles, 130)
        XCTAssertEqual(clock.hhmm(plan.entries[2].start), "11:45")
        XCTAssertEqual(plan.entries.last!.from, "Hotel – Spokane, WA")
        XCTAssertEqual(clock.hhmm(plan.entries.last!.end!), "17:00")
        try validate(Log(entries: plan.entries), now: plan.entries.last!.end!)
        XCTAssertEqual(readLdDay(plan.entries, zone: pacific), day)
        XCTAssertNil(readSimpleDay(plan.entries, zone: pacific))
    }

    func testLdHotelUnloadOfficeAndReadBack() throws {
        let day = LdDay(date: "2025-03-04", start: LdPlace(at: .hotel, office: .kent, hotel: "Spokane"), unload: "Yakima", end: LdPlace(at: .office, office: .kent))
        let plan = try planLdDay(day, zone: pacific)
        XCTAssertEqual(plan.miles, 326)
        XCTAssertEqual(plan.entries.count, 7)
        XCTAssertEqual(plan.route, ["Hotel (Spokane)", "Yakima", "Kent office"])
        XCTAssertEqual(plan.entries.filter { $0.note == "Unloading" }.count, 2)
        XCTAssertEqual(readLdDay(plan.entries, zone: pacific), day)
    }

    func testLdChecks() {
        XCTAssertThrowsError(try planLdDay(LdDay(date: "2025-03-04", end: LdPlace(at: .office)), zone: pacific))
        XCTAssertThrowsError(try planLdDay(LdDay(date: "2025-03-04", unload: " ", end: LdPlace(at: .hotel, hotel: "Spokane")), zone: pacific))
        let unknown = LdDay(date: "2025-03-04", start: LdPlace(at: .hotel, hotel: "Missoula, MT"), end: LdPlace(at: .hotel, hotel: "Spokane"), clockIn: "06:00", clockOut: "16:00", lunch: 0)
        XCTAssertThrowsError(try planLdDay(unknown, zone: pacific))
        var withMiles = unknown
        withMiles.miles = 300
        XCTAssertEqual(try planLdDay(withMiles, zone: pacific).entries.count, 3)
        XCTAssertEqual(try readLdDay(planLdDay(withMiles, zone: pacific).entries, zone: pacific), withMiles)
    }

    func testFindCity() {
        XCTAssertEqual(Cities.find("123 Main St, Kent, WA 98032")?.name, "Kent")
        XCTAssertEqual(Cities.find("issaq")?.name, "Issaquah")
        XCTAssertEqual(Cities.find("Issaquah High")?.name, "Issaquah Highlands")
        XCTAssertEqual(Cities.find("Coeur dAlene, ID 83814")?.name, "Coeur d'Alene")
        XCTAssertNil(Cities.find("Bell"))
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

    // MARK: LD flow, chart and hours of service (matches lib/hos.ts on the website)

    private func ldSteps(_ day: String) throws -> [TimelineStep] {
        var prev: Date?
        func at(_ t: String, _ step: Step, _ place: String) throws -> TimelineStep {
            let time = try clock.stepTime(day: day, t, after: prev)
            prev = time
            return TimelineStep(time: time, step: step, place: place)
        }
        return [try at("06:30", .act(.pretrip), Places.preston), try at("06:45", .act(.drive), Places.preston),
                try at("09:30", .act(.fuel), "Ellensburg"), try at("09:45", .act(.drive), "Ellensburg"),
                try at("11:30", .act(.lunch), "Spokane"), try at("12:00", .act(.unload), "Spokane"),
                try at("15:00", .act(.drive), "Spokane"), try at("16:30", .act(.posttrip), Places.hotel("Spokane Valley")),
                try at("16:45", .clockOut, Places.hotel("Spokane Valley"))]
    }

    func testTimelineRoundTripAndChart() throws {
        let steps = try ldSteps("2026-11-20")
        let es = try toEntries(steps, tag: Places.ldMark)
        XCTAssertEqual(es.count, 8)
        XCTAssertEqual(es.map(\.status), [.onDuty, .driving, .onDuty, .driving, .offDuty, .onDuty, .driving, .onDuty])
        XCTAssertEqual(es[1].miles, 92.9)
        XCTAssertEqual(es[3].to, "Spokane")
        XCTAssertTrue(es[0].note.hasSuffix(Places.ldMark))
        try validate(Log(entries: es), now: es.last!.end!)
        XCTAssertEqual(toSteps(es).map(\.step), steps.map(\.step))
        XCTAssertEqual(toSteps(es).map(\.time), steps.map(\.time))
        let chart = Chart(entries: es, day: "2026-11-20", clock: clock, now: Date())
        XCTAssertEqual(chart.totals.values.reduce(0, +), 24 * 3600)
        XCTAssertEqual(chart.totals[.driving], 6 * 3600)
        XCTAssertEqual(chart.remarks.count, 8)
        XCTAssertEqual(chart.clockOut?.id, es.last!.id)
        XCTAssertTrue(isLdDay(es))
    }

    func testPastMidnightSplitsAcrossDays() throws {
        var prev: Date?
        let steps = try [("20:00", Step.act(.pretrip)), ("20:15", .act(.drive)), ("01:00", .act(.posttrip)), ("01:15", .clockOut)].map { t, s -> TimelineStep in
            let time = try clock.stepTime(day: "2026-11-20", t, after: prev); prev = time
            return TimelineStep(time: time, step: s, place: "Boise")
        }
        let es = try toEntries(steps)
        XCTAssertEqual(clock.dayKey(es.last!.end!), "2026-11-21")
        let day2 = Chart(entries: es, day: "2026-11-21", clock: clock, now: Date())
        XCTAssertEqual(day2.totals[.driving], 3600)
        XCTAssertEqual(day2.totals.values.reduce(0, +), 24 * 3600)
    }

    func testStepAtRoundsUpAndNamesTheTime() throws {
        let now = try clock.date(day: "2026-11-26", time: "08:19").addingTimeInterval(14)
        let drive = try clock.date(day: "2026-11-26", time: "08:20")
        // Saved a minute ahead (the reported bug): a later pick still works.
        XCTAssertEqual(try clock.stepAt("08:21", now: now, after: drive), now.addingTimeInterval(55))
        XCTAssertThrowsError(try clock.stepAt("08:19", now: now, after: drive)) { XCTAssertTrue("\($0.localizedDescription)".contains("8:20 AM")) }
        XCTAssertEqual(try clock.stepAt("08:19", now: now, after: drive.addingTimeInterval(-120)), try clock.date(day: "2026-11-26", time: "08:19"))
        XCTAssertEqual(try clock.stepAt("23:00", now: now), try clock.date(day: "2026-11-25", time: "23:00"))
        XCTAssertThrowsError(try clock.stepAt("23:00", now: now, after: try clock.date(day: "2026-11-26", time: "07:00")))
    }

    func testShiftPastMidnightEditsAsOne() throws {
        var prev: Date?
        func at(_ day: String, _ t: String, _ s: Step, _ place: String) throws -> TimelineStep {
            let time = try clock.stepTime(day: day, t, after: prev); prev = time
            return TimelineStep(time: time, step: s, place: place)
        }
        let night = try toEntries([try at("2026-11-20", "20:00", .act(.pretrip), Places.preston), try at("2026-11-20", "20:15", .act(.drive), Places.preston),
                                   try at("2026-11-20", "01:00", .act(.posttrip), "Boise"), try at("2026-11-20", "01:15", .clockOut, "Boise")])
        XCTAssertEqual(shiftOf(night, day: "2026-11-20", clock: clock).entries.map(\.id), night.map(\.id))
        let back = shiftOf(night, day: "2026-11-21", clock: clock)
        XCTAssertEqual(back.day, "2026-11-20")
        XCTAssertEqual(back.entries.count, 3)
        prev = nil
        let morning = try toEntries([try at("2026-11-21", "09:00", .act(.pretrip), "Boise"), try at("2026-11-21", "09:15", .act(.drive), "Boise"), try at("2026-11-21", "12:00", .clockOut, "Twin Falls")])
        let own = shiftOf(night + morning, day: "2026-11-21", clock: clock)
        XCTAssertEqual(own.day, "2026-11-21")
        XCTAssertEqual(own.entries.map(\.id), morning.map(\.id))
        XCTAssertTrue(shiftOf([], day: "2026-11-20", clock: clock).entries.isEmpty)
    }

    func testHosClocks() throws {
        let es = try toEntries(try ldSteps("2026-11-20"))
        let c = HosClocks(entries: es, now: try clock.date(day: "2026-11-20", time: "13:00"))
        XCTAssertEqual(c.drive, 6.5 * 3600)
        XCTAssertEqual(c.window, 7.5 * 3600)
        XCTAssertEqual(c.breakDue, 8 * 3600)
        XCTAssertEqual(c.cycle, 64 * 3600)
    }

    func testActivitiesAndSteps() {
        XCTAssertEqual(Activity.of(Entry(status: .onDuty, start: Date(), note: "Unloading (job 2)")), .unload)
        XCTAssertEqual(Activity.of(Entry(status: .onDuty, start: Date(), note: "Pre-trip inspection / prep at office | Simple day entry")), .pretrip)
        XCTAssertEqual(Activity.fuel.status, .onDuty)
        XCTAssertEqual(Activity.riding.status, .onDuty)
        XCTAssertEqual(nextSteps(nil), [.act(.pretrip)])
        XCTAssertEqual(Step.act(.drive).label(now: .riding), "Take the wheel")
        XCTAssertFalse(isLdDay([Entry(status: .driving, start: Date(), from: Places.preston, to: "Clyde Hill")]))
        XCTAssertTrue(isLdDay([Entry(status: .driving, start: Date(), from: Places.preston, to: "Pullman")]))
    }

    func testHistoryGroupsLdTrips() {
        func day(_ d: String, _ ld: Bool) -> DaySummary { DaySummary(day: d, first: Date(), last: Date(), lunch: 0, worked: 0, miles: 10, open: false, ld: ld) }
        let g = groupTrips([day("2026-11-23", false), day("2026-11-21", true), day("2026-11-20", true), day("2026-11-17", true), day("2026-11-16", false)])
        XCTAssertEqual(g.map(\.days.count), [1, 2, 1, 1])
        XCTAssertEqual(g.map(\.ld), [false, true, true, false])
    }
}
