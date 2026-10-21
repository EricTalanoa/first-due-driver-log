#if os(iOS)
import DriverLogCore
import SwiftUI

struct HistoryScreen: View {
    @EnvironmentObject var model: AppModel
    @State private var sheet: Sheet?
    @State private var choosing = false

    var body: some View {
        let months = history(model.log, now: model.now)
        let clock = model.clock
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    BrandTitle().padding(.bottom, 6)
                    HStack {
                        Eyebrow("Log history", color: Brand.ink)
                        Spacer()
                        Button { choosing = true } label: { Label("New entry", systemImage: "plus") }.buttonStyle(OutlineButtonStyle())
                    }
                    if months.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath").font(.title).foregroundStyle(Brand.muted)
                            Text("No days logged yet").font(.headline)
                            Text("Days you record or add will show up here.").font(.footnote).foregroundStyle(Brand.muted)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                    ForEach(months) { m in
                        HStack {
                            Eyebrow(Clock.label(m.month + "-01", "MMMM yyyy"))
                            Spacer()
                            Text("\(duration(m.worked)) · \(milesText(m.miles)) mi").font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(Brand.ink)
                        }
                        .padding(.top, 14)
                        ForEach(m.days) { d in
                            Button { open(d.day) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(Clock.label(d.day, "EEE, MMM d")).font(.headline)
                                        Spacer()
                                        Text(milesText(d.miles)).font(.headline).monospacedDigit() + Text(" mi").font(.subheadline).foregroundColor(Brand.muted)
                                    }
                                    HStack {
                                        Text("\(clock.time(d.first)) – \(d.open ? "now" : clock.time(d.last)) · \(duration(d.worked))").font(.subheadline).monospacedDigit()
                                        Spacer()
                                        Text(d.lunch > 0 ? "Lunch \(duration(d.lunch).replacingOccurrences(of: "0h ", with: ""))" : "No lunch").font(.footnote)
                                    }
                                    .foregroundStyle(Brand.muted)
                                }
                                .foregroundStyle(Brand.ink)
                                .padding(14)
                                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.paperLine))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .background(Brand.page.ignoresSafeArea())
            .refreshable { await model.refresh() }
            .toolbar(.hidden, for: .navigationBar)
        }
        .confirmationDialog("Add to your log", isPresented: $choosing, titleVisibility: .visible) {
            Button("Simple day") { sheet = .simple }
            Button("Advanced entry") {
                let end = Date()
                sheet = .edit(Entry(status: .driving, start: end.addingTimeInterval(-3600), end: end))
            }
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .simple: SimpleDayEditor(day: model.today)
            case .edit(let e): EntryEditor(entry: e)
            case .settings: SettingsView()
            }
        }
    }

    private func open(_ day: String) {
        model.day = day
        model.tab = .log
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var p = Profile()
    @State private var error = ""
    @State private var confirmSignOut = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Driver & vehicle") {
                    TextField("Driver’s full name", text: $p.name)
                    TextField("Truck / trailer numbers or plates", text: $p.vehicle)
                    TextField("Carrier", text: $p.carrier)
                    TextField("Home terminal address", text: $p.terminal)
                    TextField("Main office address", text: $p.office)
                    TextField("Co-driver (optional)", text: $p.coDriver)
                    Picker("Home-terminal timezone", selection: $p.zone) {
                        ForEach(Profile.zones, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                    }
                }
                if !error.isEmpty { Section { Text(error).foregroundStyle(.red) } }
                Section("Your data") {
                    ShareLink(item: csvFile(), preview: SharePreview("Driver log (CSV)")) {
                        Label("Export every entry (CSV)", systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.log.all.isEmpty)
                }
                Section("Account") {
                    Button("Sign out") { confirmSignOut = true }
                    Button("Delete account", role: .destructive) { confirmDelete = true }
                }
                Section {
                    Text("GPS mileage is an estimate from your phone's location and does not use road routing. Confirm miles with the odometer. This personal logbook is not a certified ELD.")
                        .font(.footnote).foregroundStyle(Brand.muted)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.busy ? "Saving…" : "Save") {
                        Task {
                            do { try await model.saveProfile(p); dismiss() } catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(model.busy || p == model.log.profile)
                }
            }
            .onAppear { p = model.log.profile }
            // If Settings opened before the log finished loading, fill in the details once they arrive.
            .onChange(of: model.log.profile) { old, new in if p == old { p = new } }
            .alert("Sign out?", isPresented: $confirmSignOut) {
                Button("Sign out", role: .destructive) { Task { dismiss(); await model.signOut() } }
            } message: { Text("Your log stays saved in your account.") }
            .alert("Delete your account?", isPresented: $confirmDelete) {
                Button("Delete account and log", role: .destructive) { Task { dismiss(); await model.deleteAccount() } }
            } message: { Text("This permanently deletes your account and every entry in your log, on the web and in the app. Export a CSV first if you want a copy.") }
        }
    }

    /// Every entry as a CSV file, same columns as the website plus the date.
    private func csvFile() -> URL {
        let clock = model.clock
        let zone = model.log.profile.zone
        func cell(_ v: String) -> String {
            var s = v
            if let f = s.first, "=+@-".contains(f) { s = "'" + s }
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var lines = [["Date", "Status", "Start (\(zone))", "End (\(zone))", "From", "To", "Miles (whole trip)", "Distance source", "Check distance", "Remarks", "Document", "Shipper", "Commodity"].map(cell).joined(separator: ",")]
        for e in model.log.all.sorted(by: { $0.start < $1.start }) {
            lines.append([clock.dayKey(e.start), e.status.rawValue, clock.localInput(e.start), e.end.map(clock.localInput) ?? "Active", e.from, e.to,
                          e.miles.map { String($0) } ?? "", e.source.rawValue, e.partial ? "Yes" : "No", e.note, e.document ?? "", e.shipper ?? "", e.commodity ?? ""]
                .map(cell).joined(separator: ","))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("driver-log-all-\(model.today).csv")
        try? lines.joined(separator: "\r\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
#endif
