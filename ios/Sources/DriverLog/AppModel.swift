#if os(iOS)
import DriverLogCore
import Foundation
import SwiftUI

/// Everything the screens show and do. Mirrors the website's logic: each action builds the
/// next version of the log, saves only what changed, then shows it.
@MainActor
final class AppModel: ObservableObject {
    enum Phase { case checking, signedOut, signedIn }
    enum Tab: Hashable { case today, ld, history }

    @Published var phase: Phase = .checking
    @Published var tab: Tab = .today
    @Published private(set) var log = Log()
    @Published private(set) var loaded = false
    @Published private(set) var busy = false
    @Published var error: String?
    @Published var toast: String?
    @Published var day = ""
    @Published private(set) var now = Date()
    @Published var canUseGoogle = false

    let backend: Backend
    private var ticker: Timer?

    init(backend: Backend) {
        self.backend = backend
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
    }

    var clock: Clock { Clock(zone: log.profile.timeZone) }
    var today: String { clock.dayKey(now) }
    var active: Entry? { log.active }
    var driving: Bool { log.active?.status == .driving }

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
        } catch where isCancellation(error) {
            // A load cut off part-way (a redraw, the app going to the background) isn't a failure: try once more quietly.
            if retrying { await Task { await self.load(retrying: false) }.value }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOut() async {
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

    // MARK: LD steps

    /// GPS tracking is shelved (it is in the git history before this change). Each LD step closes what the
    /// driver was doing at `at` and starts the next activity. Returns the ended drive if it still needs miles.
    @discardableResult
    func take(_ step: Step, at: Date, place: String, miles: Double?) async throws -> Entry? {
        var next = log
        var ended: Entry?
        if var a = log.active {
            guard at > a.start else { throw LogError("What you're doing now started at \(clock.time(a.start)). Pick a time after that.") }
            a.end = at
            if a.status == .driving {
                a.to = place
                a.miles = miles ?? Places.estimateMiles(a.from, place) ?? a.miles
                a.partial = false
                a.source = .manual
            }
            next.entries.append(a)
            ended = a
        }
        if case .act(let act) = step {
            next.active = Entry(status: act.status, start: at, from: place, note: act.note + (act == .pretrip ? Places.ldMark : ""))
        } else {
            next.active = nil
        }
        try await save(next, message: step == .clockOut ? "Clocked out" : "Saved")
        day = clock.dayKey(at)
        return ended?.status == .driving && ended?.miles == nil ? ended : nil
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

    /// Whether what is being recorded now falls on `day` (Clear day removes it too).
    func recording(on day: String) -> Bool { log.active.map { $0.start < clock.bounds(day).end } ?? false }

    /// Clear day: deletes the whole day and starts it over, including a drive or work being recorded now.
    func clear(day: String) async throws {
        let gone = Set(entries(startingOn: day).map(\.id))
        let drop = recording(on: day)
        var next = log
        next.entries.removeAll { gone.contains($0.id) }
        if drop { next.active = nil }
        let n = gone.count + (drop ? 1 : 0)
        try await save(next, message: "Cleared \(n) \(n == 1 ? "entry" : "entries")")
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
