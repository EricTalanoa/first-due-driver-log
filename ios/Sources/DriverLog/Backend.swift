#if os(iOS)
import Foundation
import DriverLogCore
import Supabase

/// Where the log lives. The app uses Supabase; CI screenshots use sample data.
protocol Backend: AnyObject {
    var isSignedIn: Bool { get async }
    var canUseGoogle: Bool { get async }
    func signIn(email: String, password: String) async throws
    /// Returns true when the account still needs its email confirmed.
    func signUp(email: String, password: String) async throws -> Bool
    func signInWithGoogle() async throws
    /// Sign in with Apple: the identity token Apple returned, and the raw nonce whose SHA-256 was sent with the request.
    func signInWithApple(idToken: String, nonce: String) async throws
    func signOut() async
    func load() async throws -> Log
    func save(_ change: LogChange) async throws
    func deleteAccount() async throws
    func handle(_ url: URL)
    /// Whether this account has seen the first-launch tutorial (kept with the account, on every phone).
    var tutorialSeen: Bool { get async }
    func markTutorialSeen() async throws
}

enum SupabaseConfig {
    // Publishable values, the same ones the website uses. Row-level security keeps each driver's rows private.
    static let url = URL(string: "https://jtofziwssarbifugqjnn.supabase.co")!
    static let key = "sb_publishable_noucvZct2WKRH3RxzuHpAw_i8Ln_JgJ"
    /// Must be listed under Supabase → Authentication → URL Configuration → Redirect URLs.
    static let callback = URL(string: "firstduedriverlog://login-callback")!
}

final class SupabaseBackend: Backend {
    let client = SupabaseClient(supabaseURL: SupabaseConfig.url, supabaseKey: SupabaseConfig.key)

    var isSignedIn: Bool {
        get async { (try? await client.auth.session) != nil }
    }

    var canUseGoogle: Bool {
        get async {
            var request = URLRequest(url: SupabaseConfig.url.appendingPathComponent("auth/v1/settings"))
            request.setValue(SupabaseConfig.key, forHTTPHeaderField: "apikey")
            struct Settings: Decodable { struct External: Decodable { let google: Bool? }; let external: External? }
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let s = try? JSONDecoder().decode(Settings.self, from: data) else { return false }
            return s.external?.google == true
        }
    }

    func signIn(email: String, password: String) async throws {
        do { _ = try await client.auth.signIn(email: email, password: password) } catch { throw friendly(error) }
    }

    func signUp(email: String, password: String) async throws -> Bool {
        do {
            _ = try await client.auth.signUp(email: email, password: password, redirectTo: URL(string: "https://first-due-driver-log-eric.netlify.app/"))
            return client.auth.currentSession == nil
        } catch { throw friendly(error) }
    }

    func signInWithGoogle() async throws {
        do { _ = try await client.auth.signInWithOAuth(provider: .google, redirectTo: SupabaseConfig.callback) } catch { throw friendly(error) }
    }

    func signInWithApple(idToken: String, nonce: String) async throws {
        do { _ = try await client.auth.signInWithIdToken(credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)) } catch { throw friendly(error) }
    }

    func signOut() async { try? await client.auth.signOut() }

    func handle(_ url: URL) { client.auth.handle(url) }

    var tutorialSeen: Bool {
        get async {
            // If the account can't be read (offline), don't interrupt with the tutorial.
            guard let user = (try? await client.auth.user()) ?? client.auth.currentUser else { return true }
            if case .bool(true)? = user.userMetadata["tutorial_seen"] { return true }
            return false
        }
    }

    func markTutorialSeen() async throws {
        _ = try await client.auth.update(user: UserAttributes(data: ["tutorial_seen": .bool(true)]))
    }

    func load() async throws -> Log {
        do {
            let profiles: [ProfileRow] = try await client.from("profiles").select("name,carrier,terminal,office,vehicle,co_driver,zone").execute().value
            var rows: [EntryRow] = []
            // Supabase returns at most 1000 rows per request, so page through.
            var from = 0
            while true {
                let page: [EntryRow] = try await client.from("entries")
                    .select("id,status,start_at,end_at,from_place,to_place,miles,note,partial,source,last_point,document,shipper,commodity")
                    .order("start_at").range(from: from, to: from + 999).execute().value
                rows += page
                if page.count < 1000 { break }
                from += 1000
            }
            return makeLog(rows: rows, profile: profiles.first)
        } catch { throw friendly(error) }
    }

    private struct SaveParams: Encodable, Sendable {
        let upserts: [EntryRow]
        let deletes: [String]
        let profile: Profile?
    }

    func save(_ change: LogChange) async throws {
        guard !change.isEmpty else { return }
        do {
            try await client.rpc("save_log", params: SaveParams(upserts: change.upserts, deletes: change.deletes, profile: change.profile)).execute()
        } catch { throw friendly(error) }
    }

    func deleteAccount() async throws {
        do {
            try await client.rpc("delete_my_account").execute()
            await signOut()
        } catch { throw friendly(error) }
    }

    private func friendly(_ error: Error) -> Error {
        if isCancellation(error) { return CancellationError() }
        if let e = error as? PostgrestError {
            // The app checks overlaps before saving, so a clash means the log was changed on another device.
            if e.code == "23P01" { return StaleLogError() }
            if e.code == "42501" || e.code == "PGRST301" { return LogError("Your sign-in expired. Sign in again; your open form is still here.") }
            return LogError(e.message)
        }
        if let e = error as? URLError {
            if e.code == .cancelled || e.code == .userCancelledAuthentication { return CancellationError() }
            return LogError("Could not reach the server. Check your connection and try again.")
        }
        let text = String(describing: error)
        if text.localizedCaseInsensitiveContains("invalid login") { return LogError("Email or password is incorrect.") }
        if text.localizedCaseInsensitiveContains("email not confirmed") { return LogError("Confirm your email first: open the link we sent you, then sign in.") }
        if text.localizedCaseInsensitiveContains("canceledLogin") || text.localizedCaseInsensitiveContains("cancel") { return CancellationError() }
        return LogError(error.localizedDescription)
    }
}

/// The saved log no longer matches this phone's copy (it was changed on the website or another device).
struct StaleLogError: LocalizedError {
    var errorDescription: String? { "Your log changed on another device. It has been refreshed: check it, then try again." }
}

/// In-memory sample data for simulator screenshots: `-demo off|ld`.
/// `ld` adds a two-day LD trip last week and an LD day in progress today (driving after a fuel stop).
final class DemoBackend: Backend {
    private var log: Log

    init(state: String, now: Date = Date()) {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let clock = Clock(zone: zone)
        let today = clock.dayKey(now)
        var entries: [Entry] = []
        let trip = state == "ld" ? [5, 4] : []
        for back in 1...24 where back % 7 != 0 && back % 7 != 6 && !trip.contains(back) {
            let day = Clock.shift(today, by: -back)
            let jobs = [Job(load: ["Issaquah", "Bellevue", "Renton", "Kirkland"][back % 4], unload: ["Seattle", "Redmond", "Kent", "Bothell"][back % 4])]
            if let plan = try? planSimpleDay(SimpleDay(date: day, jobs: jobs, clockIn: "07:45", clockOut: back % 2 == 0 ? "16:30" : "15:45"), zone: zone) {
                entries += plan.entries
            }
        }
        var active: Entry?
        if state == "ld" {
            func steps(_ day: String, _ list: [(String, Step, String)]) -> [Entry] {
                var prev: Date?
                let s = list.compactMap { t, step, place -> TimelineStep? in
                    guard let at = try? clock.stepTime(day: day, t, after: prev) else { return nil }
                    prev = at
                    return TimelineStep(time: at, step: step, place: place)
                }
                return (try? toEntries(s, tag: Places.ldMark)) ?? []
            }
            entries += steps(Clock.shift(today, by: -5), [("07:00", .act(.pretrip), Places.preston), ("07:15", .act(.drive), Places.preston),
                                                         ("10:00", .act(.fuel), "Ellensburg"), ("10:15", .act(.drive), "Ellensburg"),
                                                         ("12:30", .act(.lunch), "Richland"), ("13:00", .act(.drive), "Richland"),
                                                         ("14:15", .act(.posttrip), Places.hotel("Walla Walla")), ("14:30", .clockOut, Places.hotel("Walla Walla"))])
            entries += steps(Clock.shift(today, by: -4), [("08:00", .act(.pretrip), Places.hotel("Walla Walla")), ("08:15", .act(.drive), Places.hotel("Walla Walla")),
                                                         ("08:45", .act(.unload), "Walla Walla"), ("13:00", .act(.lunch), "Walla Walla"),
                                                         ("13:30", .act(.drive), "Walla Walla"), ("18:00", .act(.posttrip), Places.preston), ("18:15", .clockOut, Places.preston)])
            let start = now.addingTimeInterval(-3 * 3600)
            entries.append(Entry(status: .onDuty, start: start, end: start.addingTimeInterval(900), from: Places.preston, note: Activity.pretrip.note + Places.ldMark))
            entries.append(Entry(status: .driving, start: start.addingTimeInterval(900), end: start.addingTimeInterval(7200), from: Places.preston, to: "Ellensburg, WA", miles: 92.9, note: "Driving"))
            entries.append(Entry(status: .onDuty, start: start.addingTimeInterval(7200), end: start.addingTimeInterval(8100), from: "Ellensburg, WA", note: Activity.fuel.note))
            active = Entry(status: .driving, start: start.addingTimeInterval(8100), from: "Ellensburg, WA", note: "Driving")
        }
        log = Log(entries: entries, active: active, profile: Profile(name: "Sample Driver", vehicle: "12", coDriver: ""))
    }

    var isSignedIn: Bool { get async { true } }
    var canUseGoogle: Bool { get async { true } }
    /// Sample data skips the tutorial unless launched with `-tutorial show`.
    private var seen = LaunchOptions.tutorial != "show"
    var tutorialSeen: Bool { get async { seen } }
    func markTutorialSeen() async throws { seen = true }
    func signIn(email: String, password: String) async throws {}
    func signUp(email: String, password: String) async throws -> Bool { false }
    func signInWithGoogle() async throws {}
    func signInWithApple(idToken: String, nonce: String) async throws {}
    func signOut() async {}
    func load() async throws -> Log { log }
    func save(_ change: LogChange) async throws {}
    func deleteAccount() async throws {}
    func handle(_ url: URL) {}
}
#endif
