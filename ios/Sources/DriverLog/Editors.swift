#if os(iOS)
import DriverLogCore
import SwiftUI

/// Office, jobs, clock times and lunch; the whole day is filled in. Reopens a saved Simple day for editing.
struct SimpleDayEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let day: String
    @State private var v = SimpleDay(date: "")
    @State private var prior = false
    @State private var replace = false
    @State private var error = ""
    @State private var ready = false
    @State private var milesInput = ""

    private static let defaultsKey = "simple-defaults"
    private struct Remembered: Codable { var office: Office; var clockIn: String; var clockOut: String; var lunch: Int }

    var body: some View {
        let zone = model.log.profile.timeZone
        let others = model.entries(startingOn: v.date)
        let complete = v.jobs.allSatisfy { !$0.load.trimmingCharacters(in: .whitespaces).isEmpty && !$0.unload.trimmingCharacters(in: .whitespaces).isEmpty }
        let attempt: Result<Plan, Error>? = complete && ready ? Result { try planSimpleDay(v, zone: zone, newID: { "preview" }) } : nil
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DatePicker("Date", selection: dateBinding(zone), displayedComponents: .date)
                        .font(.subheadline.weight(.semibold))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Starting office").font(.subheadline.weight(.semibold))
                        Picker("Starting office", selection: $v.office) {
                            ForEach(Office.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    ForEach(Array(v.jobs.enumerated()), id: \.offset) { i, _ in
                        VStack(alignment: .leading, spacing: 10) {
                            if v.jobs.count > 1 {
                                HStack {
                                    Text("Job \(i + 1)").font(.subheadline.weight(.bold))
                                    Spacer()
                                    Button("Remove") { if i < v.jobs.count { v.jobs.remove(at: i) } }.font(.subheadline.weight(.semibold))
                                }
                            }
                            CityField(label: "Load city", placeholder: "e.g. Issaquah", text: job(i, \.load))
                            CityField(label: "Unload city", placeholder: "e.g. Seattle", text: job(i, \.unload))
                        }
                        .padding(v.jobs.count > 1 ? 12 : 0)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(v.jobs.count > 1 ? Brand.paperLine : .clear))
                    }
                    if v.jobs.count < 4 {
                        Button { v.jobs.append(Job()) } label: { Label("Add another job", systemImage: "plus") }
                            .font(.subheadline.weight(.semibold))
                    }
                    HStack(spacing: 12) {
                        TimeField(label: "Clock in", value: $v.clockIn)
                        TimeField(label: "Clock out", value: $v.clockOut)
                    }
                    HStack {
                        Text("Lunch").font(.subheadline.weight(.semibold))
                        Spacer()
                        Picker("Lunch", selection: $v.lunch) {
                            ForEach(Array(Set([0, 15, 30, 45, 60, v.lunch])).sorted(), id: \.self) { Text($0 == 0 ? "No lunch" : "\($0) minutes").tag($0) }
                        }
                    }
                    if v.miles != nil || (attempt.flatMap { try? $0.get() } == nil && attempt != nil) {
                        TextField("From your odometer", text: $milesInput).keyboardType(.decimalPad).field("Total miles for the day")
                            .onChange(of: milesInput) { _, text in v.miles = text.isEmpty ? nil : Double(text.replacingOccurrences(of: ",", with: ".")) ?? v.miles }
                    }
                    switch attempt {
                    case .success(let plan):
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(milesText(plan.miles)) mi · \(duration(TimeInterval(plan.driveMinutes * 60))) driving").font(.title3.weight(.bold))
                            Text(plan.route.joined(separator: " → ")).font(.subheadline).foregroundStyle(Brand.onDark)
                            if v.miles == nil {
                                Button("Use odometer miles instead") { v.miles = plan.miles; milesInput = milesText(plan.miles) }.font(.subheadline.weight(.semibold)).foregroundStyle(Color(red: 1, green: 0.61, blue: 0.58))
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Brand.card, in: RoundedRectangle(cornerRadius: 10))
                    case .failure(let e):
                        Note(text: e.localizedDescription)
                    case nil:
                        EmptyView()
                    }
                    if !others.isEmpty {
                        Toggle(isOn: $replace) {
                            Text("Replace the \(others.count) \(others.count == 1 ? "entry" : "entries") already logged on this date").font(.subheadline)
                        }
                        .padding(12).background(Brand.warnBackground, in: RoundedRectangle(cornerRadius: 8))
                    }
                    if !error.isEmpty { Text(error).font(.subheadline).foregroundStyle(.red) }
                }
                .padding(20)
            }
            .navigationTitle(prior ? "Edit day" : "Simple day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.busy ? "Saving…" : prior ? "Save day" : "Add day") { Task { await submit(zone) } }
                        .disabled(model.busy || (try? attempt?.get()) == nil)
                }
            }
        }
        .onAppear { setUp(zone) }
    }

    private func setUp(_ zone: TimeZone) {
        guard !ready else { return }
        if let saved = readSimpleDay(model.entries(startingOn: day), zone: zone) {
            v = saved
            milesInput = saved.miles.map(milesText) ?? ""
            prior = true
            replace = true
        } else {
            v = SimpleDay(date: day)
            if let data = UserDefaults.standard.data(forKey: Self.defaultsKey), let r = try? JSONDecoder().decode(Remembered.self, from: data) {
                v.office = r.office; v.clockIn = r.clockIn; v.clockOut = r.clockOut; v.lunch = r.lunch
            }
        }
        ready = true
    }

    private func submit(_ zone: TimeZone) async {
        error = ""
        do {
            let plan = try planSimpleDay(v, zone: zone)
            if let data = try? JSONEncoder().encode(Remembered(office: v.office, clockIn: v.clockIn, clockOut: v.clockOut, lunch: v.lunch)) {
                UserDefaults.standard.set(data, forKey: Self.defaultsKey)
            }
            try await model.saveSimpleDay(plan.entries, date: v.date, replace: replace && !model.entries(startingOn: v.date).isEmpty)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// A binding to one job's city that survives the job being removed.
    private func job(_ i: Int, _ key: WritableKeyPath<Job, String>) -> Binding<String> {
        Binding(get: { i < v.jobs.count ? v.jobs[i][keyPath: key] : "" },
                set: { if i < v.jobs.count { v.jobs[i][keyPath: key] = $0 } })
    }

    private func dateBinding(_ zone: TimeZone) -> Binding<Date> {
        let clock = Clock(zone: zone)
        return Binding(get: { (try? clock.date(day: v.date, time: "12:00")) ?? Date() }, set: { v.date = clock.dayKey($0) })
    }
}

/// A text field with city suggestions from the planner's list.
struct CityField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        let matches = text.count >= 2 ? Cities.names.filter { $0.lowercased().hasPrefix(text.lowercased()) && $0 != text }.prefix(4) : []
        VStack(alignment: .leading, spacing: 6) {
            TextField(placeholder, text: $text).textInputAutocapitalization(.words).autocorrectionDisabled().focused($focused).field(label)
            if focused && !matches.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Array(matches), id: \.self) { name in
                            Button(name) { text = name; focused = false }
                                .font(.subheadline).padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Brand.page, in: Capsule())
                        }
                    }
                }
            }
        }
    }
}

/// "HH:mm" text bound to a time picker.
struct TimeField: View {
    let label: String
    @Binding var value: String

    var body: some View {
        let zone = TimeZone(identifier: "UTC")!
        let clock = Clock(zone: zone)
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.weight(.semibold))
            DatePicker(label, selection: Binding(
                get: { (try? clock.date(day: "2000-01-01", time: value)) ?? Date() },
                set: { value = clock.hhmm($0) }
            ), displayedComponents: .hourAndMinute)
            .labelsHidden()
            .environment(\.timeZone, zone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Note: View {
    let text: String
    var body: some View {
        Text(text).font(.subheadline).foregroundStyle(Color(red: 0.46, green: 0.31, blue: 0.04))
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.warnBackground, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// One duty period with exact times, places and miles.
struct EntryEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let entry: Entry
    @State private var value: Entry
    @State private var milesText: String
    @State private var milesChanged = false
    @State private var error = ""
    @State private var confirmDelete = false

    init(entry: Entry) {
        self.entry = entry
        _value = State(initialValue: entry)
        _milesText = State(initialValue: entry.miles.map { String(format: "%.1f", $0) } ?? "")
    }

    var body: some View {
        let saved = model.log.entries.contains { $0.id == entry.id }
        NavigationStack {
            Form {
                Section {
                    if entry.partial {
                        Note(text: "GPS may be incomplete. Enter the actual distance from your odometer to confirm it.")
                    }
                    Picker("Duty status", selection: $value.status) {
                        ForEach(Status.allCases) { Text($0.rawValue).tag($0) }
                    }
                    DatePicker("Start", selection: $value.start)
                    DatePicker("End", selection: Binding(get: { value.end ?? Date() }, set: { value.end = $0 }))
                } footer: {
                    Text("Times use \(model.log.profile.zone.replacingOccurrences(of: "_", with: " ")).")
                }
                .environment(\.timeZone, model.log.profile.timeZone)
                Section("Trip") {
                    TextField("From · address or place", text: $value.from)
                    TextField("To · address or place", text: $value.to)
                    TextField("Distance · miles", text: $milesText).keyboardType(.decimalPad)
                        .onChange(of: milesText) { _, _ in milesChanged = true }
                }
                Section("Remarks") {
                    TextField("Optional notes", text: $value.note, axis: .vertical).lineLimit(2...5)
                }
                Section("Shipping details (optional)") {
                    TextField("Manifest / document number", text: Binding(get: { value.document ?? "" }, set: { value.document = $0.isEmpty ? nil : $0 }))
                    TextField("Name of shipper", text: Binding(get: { value.shipper ?? "" }, set: { value.shipper = $0.isEmpty ? nil : $0 }))
                    TextField("Commodity", text: Binding(get: { value.commodity ?? "" }, set: { value.commodity = $0.isEmpty ? nil : $0 }))
                }
                if !error.isEmpty { Section { Text(error).foregroundStyle(.red) } }
                if saved {
                    Section { Button("Delete entry", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(entry.source == .gps ? "Review your trip" : "Log entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(model.busy ? "Saving…" : "Save") { Task { await submit() } }.disabled(model.busy) }
            }
            .alert("Delete this entry?", isPresented: $confirmDelete) {
                Button("Delete entry", role: .destructive) {
                    Task {
                        do { try await model.delete(entry.id); dismiss() } catch { self.error = error.localizedDescription }
                    }
                }
            } message: { Text("This removes the duty period from your saved log.") }
        }
    }

    private func submit() async {
        error = ""
        var e = value
        let trimmed = milesText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { e.miles = nil }
        else if let m = Double(trimmed), m >= 0 { e.miles = m }
        else { error = "Enter a valid distance."; return }
        if milesChanged { e.partial = false; e.source = .manual }
        guard let end = e.end, end > e.start else { error = "End time must be after start time."; return }
        do {
            try await model.saveEntry(e)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
#endif
