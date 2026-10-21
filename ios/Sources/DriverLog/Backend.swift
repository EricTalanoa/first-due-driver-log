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
    func signOut() async
    func load() async throws -> Log
    func save(_ change: LogChange) async throws
    func deleteAccount() async throws
    func handle(_ url: URL)
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

    func signOut() async { try? await client.auth.signOut() }

    func handle(_ url: URL) { client.auth.handle(url) }

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
        if let e = error as? PostgrestError {
            if e.code == "23P01" { return LogError("Duty periods cannot overlap. Adjust the times first.") }
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

/// In-memory sample data for simulator screenshots: `-demo off|clocked|driving`.
final class DemoBackend: Backend {
    private var log: Log

    init(state: String, now: Date = Date()) {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let clock = Clock(zone: zone)
        var entries: [Entry] = []
        for back in 1...24 where back % 7 != 0 && back % 7 != 6 {
            let day = Clock.shift(clock.dayKey(now), by: -back)
            let jobs = [Job(load: ["Issaquah", "Bellevue", "Renton", "Kirkland"][back % 4], unload: ["Seattle", "Redmond", "Kent", "Bothell"][back % 4])]
            if let plan = try? planSimpleDay(SimpleDay(date: day, office: back % 3 == 0 ? .kent : .preston, jobs: jobs, clockIn: "07:45", clockOut: back % 2 == 0 ? "16:30" : "15:45"), zone: zone) {
                entries += plan.entries
            }
        }
        var active: Entry?
        let start = now.addingTimeInterval(-2.5 * 3600)
        switch state {
        case "clocked":
            entries.append(Entry(status: .onDuty, start: start, end: start.addingTimeInterval(2400), from: Office.preston.label, note: "Pre-trip and loading prep"))
            entries.append(Entry(status: .driving, start: start.addingTimeInterval(2400), end: start.addingTimeInterval(3900), from: Office.preston.label, to: "Issaquah, WA", miles: 6.6, source: .gps))
            active = Entry(status: .onDuty, start: start.addingTimeInterval(3900), from: "Issaquah, WA")
        case "driving":
            entries.append(Entry(status: .onDuty, start: start, end: start.addingTimeInterval(5400), from: "Issaquah, WA", note: "Loading"))
            active = Entry(status: .driving, start: start.addingTimeInterval(5400), from: "Issaquah, WA", to: "Bellevue, WA", miles: 9.7, source: .gps)
        default:
            break
        }
        log = Log(entries: entries, active: active, profile: Profile(name: "Eric Talanoa", vehicle: "12"))
    }

    var isSignedIn: Bool { get async { true } }
    var canUseGoogle: Bool { get async { true } }
    func signIn(email: String, password: String) async throws {}
    func signUp(email: String, password: String) async throws -> Bool { false }
    func signInWithGoogle() async throws {}
    func signOut() async {}
    func load() async throws -> Log { log }
    func save(_ change: LogChange) async throws {}
    func deleteAccount() async throws {}
    func handle(_ url: URL) {}
}
#endif
