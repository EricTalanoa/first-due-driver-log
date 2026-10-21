#if os(iOS)
import Combine
import CoreLocation
import DriverLogCore
import Foundation
import SwiftUI

/// Everything the screens show and do. Mirrors the website's logic: each action builds the
/// next version of the log, saves only what changed, then shows it.
@MainActor
final class AppModel: ObservableObject {
    enum Phase { case checking, signedOut, signedIn }
    enum Tab: Hashable { case log, history }

    @Published var phase: Phase = .checking
    @Published var tab: Tab = .log
    @Published private(set) var log = Log()
    @Published private(set) var loaded = false
    @Published private(set) var busy = false
    @Published var error: String?
    @Published var toast: String?
    @Published var day = ""
    @Published private(set) var now = Date()
    @Published private(set) var meter: TripMeter?
    @Published var canUseGoogle = false

    let backend: Backend
    let tracker = LocationTracker()
    private var ticker: Timer?
    private var trackerChanges: AnyCancellable?
    private var lastFlush = Date.distantPast
    private static let meterKey = "drive-meter"

    init(backend: Backend) {
        self.backend = backend
        tracker.onFix = { [weak self] in self?.take($0) }
        // The GPS line on screen reads the tracker's state, so pass its changes through.
        trackerChanges = tracker.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
    }

    var clock: Clock { Clock(zone: log.profile.timeZone) }
    var today: String { clock.dayKey(now) }
    var active: Entry? { log.active }
    var driving: Bool { log.active?.status == .driving }
    var onClock: Bool { log.active?.status == .onDuty || driving }

    // MARK: Session

    func start() async {
        canUseGoogle = await backend.canUseGoogle
        if await backend.isSignedIn { await signedIn() } else { phase = .signedOut }
    }

    func signedIn() async {
        phase = .signedIn
        await load()
    }

    /// Pull-to-refresh: SwiftUI cancels its refresh task whenever the screen redraws (the clock ticks every
    /// second), so run the load in its own task and let the spinner wait for it.
    func refresh() async {
        await Task { await self.load() }.value
    }

    func load(retrying: Bool = true) async {
        error = nil
        do {
            let next = try await backend.load()
            log = next
            loaded = true
            if day.isEmpty { day = clock.dayKey(Date()) }
            resumeDriveIfNeeded()
        } catch where isCancellation(error) {
            // A load cut off part-way (a redraw, the app going to the background) isn't a failure: try once more quietly.
            if retrying { await Task { await self.load(retrying: false) }.value }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOut() async {
        tracker.stop()
        await backend.signOut()
        log = Log()
        loaded = false
        day = ""
        phase = .signedOut
    }

    func deleteAccount() async {
        do {
            try await backend.deleteAccount()
            await signOut()
        } catch where !isCancellation(error) {
            self.error = error.localizedDescription
        } catch {}
    }

    // MARK: Saving

    /// Saves the change from the current log to `next`. Throws so forms can stay open on failure.
    func save(_ next: Log, message: String? = "Saved") async throws {
        guard !busy else { throw LogError("Please wait for the current save.") }
        try validate(next)
        busy = true
        defer { busy = false }
        do {
            try await backend.save(DriverLogCore.change(from: log, to: next))
            log = next
            error = nil
            if let message { show(message) }
        } catch {
            if !isCancellation(error) { self.error = error.localizedDescription }
            throw error
        }
    }

    func show(_ message: String) {
        toast = message
        let shown = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if self.toast == shown { self.toast = nil }
        }
    }

    // MARK: Duty status

    /// The active entry with the latest GPS applied.
    func liveActive(at time: Date = Date()) -> Entry? {
        guard let a = log.active else { return nil }
        if a.status == .driving, let m = meter, m.entryID == a.id { return m.apply(to: a, now: time) }
        return a
    }

    /// Ends whatever is recording and starts `status`. Returns the drive that just ended, for review.
    @discardableResult
    func setStatus(_ status: Status) async -> Entry? {
        guard loaded, !busy, log.active?.status != status else { return nil }
        let at = Date()
        if driving { await finalFix() }
        let ended = liveActive(at: at).map { e -> Entry in var e = e; e.end = max(e.start.addingTimeInterval(1), at); return e }
        var next = log
        if let ended { next.entries.append(ended) }
        next.active = Entry.starting(status, at: ended?.end ?? at)
        do {
            try await save(next, message: nil)
            day = clock.dayKey(at)
            afterActiveChanged()
            return ended?.status == .driving ? ended : nil
        } catch {
            return nil
        }
    }

    /// Clock out: stop recording without starting anything new.
    func clockOut() async {
        guard loaded, !busy, log.active != nil, !driving else { return }
        let at = Date()
        var next = log
        if var a = liveActive(at: at) { a.end = max(a.start.addingTimeInterval(1), at); next.entries.append(a) }
        next.active = nil
        try? await save(next, message: "Clocked out")
        afterActiveChanged()
    }

    // MARK: GPS

    var gpsMessage: String {
        switch tracker.state {
        case .denied: return "Location is off for Driver Log · turn it on in Settings, or enter miles after the drive"
        case .unavailable: return "Location services are off · enter miles after the drive"
        case .waiting: return meter?.anchor == nil ? "Finding your location…" : "Resuming GPS…"
        case .recording: return meter?.partial == true ? "GPS had a gap · check miles afterward" : "GPS recording · works with the phone locked"
        case .idle: return ""
        }
    }

    private func afterActiveChanged() {
        if driving, let a = log.active {
            if meter?.entryID != a.id { meter = TripMeter(entry: a) }
            storeMeter()
            tracker.start()
        } else {
            meter = nil
            UserDefaults.standard.removeObject(forKey: Self.meterKey)
            tracker.stop()
        }
    }

    /// After a relaunch mid-drive, pick up this phone's meter (newer than the last server save) and keep recording.
    private func resumeDriveIfNeeded() {
        guard driving, let a = log.active else { afterActiveChanged(); return }
        if let data = UserDefaults.standard.data(forKey: Self.meterKey), let saved = try? JSONDecoder().decode(TripMeter.self, from: data),
           saved.entryID == a.id, (saved.anchor?.time ?? 0) >= (a.lastPoint?.time ?? 0) {
            meter = saved
        } else if meter?.entryID != a.id {
            meter = TripMeter(entry: a)
        }
        afterActiveChanged()
    }

    private func take(_ l: CLLocation) {
        guard var m = meter, driving else { return }
        let label = Cities.nearest(lat: l.coordinate.latitude, lon: l.coordinate.longitude).map(Cities.label)
            ?? String(format: "%.5f, %.5f", l.coordinate.latitude, l.coordinate.longitude)
        m.take(lat: l.coordinate.latitude, lon: l.coordinate.longitude, accuracy: l.horizontalAccuracy, time: l.timestamp, label: label)
        meter = m
        storeMeter()
        // Save progress to the server every 30 seconds so a lost phone doesn't lose the drive.
        if Date().timeIntervalSince(lastFlush) > 30 { Task { await flush() } }
    }

    private func storeMeter() {
        if let m = meter, let data = try? JSONEncoder().encode(m) { UserDefaults.standard.set(data, forKey: Self.meterKey) }
    }

    /// Saves the drive's GPS progress quietly.
    func flush() async {
        guard driving, !busy, let live = liveActive(), live != log.active else { return }
        lastFlush = Date()
        var next = log
        next.active = live
        try? await save(next, message: nil)
    }

    private func finalFix() async {
        guard let m = meter, Date().timeIntervalSince(m.lastFix ?? .distantPast) > 30 else { return }
        if let l = await tracker.currentFix() { take(l) }
    }

    // MARK: Days and entries

    func entries(startingOn day: String) -> [Entry] { entriesStarting(on: day, in: log) }

    func saveEntry(_ e: Entry) async throws {
        var next = log
        next.entries.removeAll { $0.id == e.id }
        next.entries.append(e)
        try await save(next)
    }

    func delete(_ id: String) async throws {
        var next = log
        next.entries.removeAll { $0.id == id }
        try await save(next, message: "Entry deleted")
    }

    func clear(day: String) async throws {
        let gone = Set(entries(startingOn: day).map(\.id))
        var next = log
        next.entries.removeAll { gone.contains($0.id) }
        try await save(next, message: "Cleared \(gone.count) entries")
    }

    func saveSimpleDay(_ entries: [Entry], date: String, replace: Bool) async throws {
        let old = replace ? Set(self.entries(startingOn: date).map(\.id)) : []
        let keep = log.entries.filter { !old.contains($0.id) }
        let clash = (keep + (log.active.map { [$0] } ?? [])).filter { k in entries.contains { overlaps(k, $0) } }
        if !clash.isEmpty {
            if clash.contains(where: { $0.id == log.active?.id }) {
                throw LogError("You are still recording \(log.active!.status.rawValue.lowercased()). Stop recording first, or change the times.")
            }
            let first = clock.time(clash.map(\.start).min()!), last = clock.time(clash.compactMap(\.end).max() ?? Date())
            throw LogError("This day already has \(clash.count) \(clash.count == 1 ? "entry" : "entries") between \(first) and \(last). \(replace ? "They start on another date; change the times." : "Turn on “Replace” above, or change the times.")")
        }
        var next = log
        next.entries = keep + entries
        try await save(next, message: "\(old.isEmpty ? "Added" : "Updated") \(Clock.label(date, "EEE, MMM d")) · \(entries.count) entries")
        day = date
    }

    func saveProfile(_ p: Profile) async throws {
        var next = log
        next.profile = p
        try await save(next, message: "Details saved")
    }
}
/// True for errors that only mean "this request was interrupted", however a library wraps them.
func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if (error as? URLError)?.code == .cancelled { return true }
    let ns = error as NSError
    if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
    return String(describing: error).contains("CancellationError") || String(reflecting: error).contains("CancellationError")
}
#endif
