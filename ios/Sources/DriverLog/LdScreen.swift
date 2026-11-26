#if os(iOS)
import DriverLogCore
import SwiftUI

// The LD tab: tap through the day (clock in, drive, stops, clock out), the hours-of-service clocks,
// the DOT chart, the inspection view and the step-by-step day editor. Mirrors app/ld-page.tsx.

struct LdScreen: View {
    @EnvironmentObject var model: AppModel
    @State private var sheet: Sheet?

    var body: some View {
        let clock = model.clock
        let today = model.today
        let t0 = clock.bounds(today).start
        let all = model.log.all
        let active = model.active
        let current = active.map(Activity.of)
        let steps = nextSteps(current)
        let loggedToday = active != nil || all.contains { $0.start >= t0 }
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack { BrandTitle(); Spacer() }
                    if let error = model.error { ErrorBanner(text: error) { Task { await model.load() } } }
                    Paper {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Eyebrow("LD · \(Clock.label(today, "EEE, MMM d"))", color: Brand.ink)
                                Text(current?.note ?? "Off the clock").font(.title.weight(.bold)).foregroundStyle(Brand.ink)
                                Text(active.map { "Since \(clock.time($0.start))\($0.from.isEmpty ? "" : " · \(Places.short($0.from))")" }
                                     ?? "Nothing logged yet today. Tap Clock in when you start your day.")
                                    .font(.subheadline).foregroundStyle(Brand.muted)
                            }
                            Spacer()
                            Text(active?.status.rawValue ?? "Off duty").font(.caption.weight(.bold)).foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Brand.color(for: active?.status ?? .offDuty), in: Capsule())
                        }
                        let lead = current != .drive && current != .riding
                        if lead, let first = steps.first {
                            Button(first.label(now: current)) { sheet = .step(first) }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(!model.loaded || model.busy)
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(lead ? Array(steps.dropFirst()) : steps, id: \.self) { s in
                                Button(s.label(now: current)) { sheet = .step(s) }
                                    .buttonStyle(StepButtonStyle())
                                    .disabled(!model.loaded || model.busy)
                            }
                        }
                        if loggedToday { ClocksView(entries: all) }
                        HosChartView(entries: all, day: today) { e in if e.id != active?.id { sheet = .edit(e) } }
                        Divider()
                        Button { sheet = .inspect } label: { Label("Inspection view", systemImage: "checkmark.shield") }.buttonStyle(OutlineButtonStyle())
                        Button { sheet = .timeline(today, ld: true) } label: { Label("Fill in or fix a day", systemImage: "list.clipboard") }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.darkRed)
                        Button { sheet = .ld } label: { Label("Estimate an LD day", systemImage: "function") }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.darkRed)
                    }
                }
                .padding(16)
            }
            .background(Brand.page.ignoresSafeArea())
            .refreshable { await model.refresh() }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $sheet) { $0.view(model) }
        .onAppear {
            switch LaunchOptions.screen {
            case "inspect": sheet = .inspect
            case "step": sheet = .step(.act(.unload))
            default: break
            }
        }
    }
}

struct StepButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(Brand.ink)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.white.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(white: 0.8)))
    }
}

/// Hours-of-service time left: 11 h driving, 14 h window, 30-minute break, 70 h in 8 days.
struct ClocksView: View {
    @EnvironmentObject var model: AppModel
    let entries: [Entry]

    var body: some View {
        let c = HosClocks(entries: entries, now: model.now)
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            tile("Driving left", c.drive, "of 11 hours")
            tile("Work window left", c.window, "of 14 hours")
            tile("Break due in", c.breakDue, "30 min after 8 h driving")
            tile("Week left", c.cycle, "of 70 hours in 8 days")
        }
    }

    private func tile(_ label: String, _ left: TimeInterval, _ of: String) -> some View {
        let over = left < 0, warn = left < 3600
        return VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Brand.muted)
            Text(over ? "Over \(duration(-left))" : duration(left)).font(.title3.weight(.bold)).monospacedDigit()
                .foregroundStyle(over ? Brand.darkRed : warn ? Brand.warn : Brand.ink)
            Text(of).font(.caption2).foregroundStyle(Brand.muted)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(over ? Color(red: 0.99, green: 0.89, blue: 0.88) : warn ? Brand.warnBackground : Brand.page, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: Chart

/// The DOT record-of-duty-status grid: 24 hours across, the four duty lines down, one continuous line,
/// a total per line, and remarks with the place of every change. Blank time is drawn as off duty.
struct HosChartView: View {
    @EnvironmentObject var model: AppModel
    let entries: [Entry]
    let day: String
    var onPick: ((Entry) -> Void)?

    private let left: CGFloat = 34, right: CGFloat = 46, top: CGFloat = 18, row: CGFloat = 28
    private let labels = ["OFF", "SB", "D", "ON"]
    @State private var width: CGFloat = 0

    var body: some View {
        let clock = model.clock
        let chart = Chart(entries: entries, day: day, clock: clock, now: model.now)
        let totals = chart.totals
        let span = chart.end.timeIntervalSince(chart.start)
        VStack(alignment: .leading, spacing: 10) {
            Canvas { ctx, size in
                let w = size.width - left - right
                let x = { (t: Date) -> CGFloat in left + CGFloat(t.timeIntervalSince(chart.start) / span) * w }
                let y = { (s: Status) -> CGFloat in top + row * CGFloat(Status.allCases.firstIndex(of: s)!) + row / 2 }
                let grid = Color(white: 0.62), tick = Color(white: 0.78)
                ctx.stroke(Path(CGRect(x: left, y: top, width: w, height: row * 4)), with: .color(Brand.ink), lineWidth: 1.2)
                for (i, label) in ["Mid", "3", "6", "9", "Noon", "3", "6", "9", "Mid"].enumerated() {
                    ctx.draw(Text(label).font(.system(size: 9)).foregroundColor(Brand.muted), at: CGPoint(x: left + w * CGFloat(i) / 8, y: top - 8))
                }
                for h in 1..<24 {
                    var p = Path(); p.move(to: CGPoint(x: left + w * CGFloat(h) / 24, y: top)); p.addLine(to: CGPoint(x: left + w * CGFloat(h) / 24, y: top + row * 4))
                    ctx.stroke(p, with: .color(grid), lineWidth: 0.5)
                }
                for (r, s) in Status.allCases.enumerated() {
                    let bottom = top + row * CGFloat(r + 1)
                    var line = Path(); line.move(to: CGPoint(x: left, y: bottom)); line.addLine(to: CGPoint(x: left + w, y: bottom))
                    ctx.stroke(line, with: .color(grid), lineWidth: 0.5)
                    for q in 0..<48 where q % 2 == 1 {
                        var t = Path(); t.move(to: CGPoint(x: left + w * CGFloat(q) / 48, y: bottom)); t.addLine(to: CGPoint(x: left + w * CGFloat(q) / 48, y: bottom - 5))
                        ctx.stroke(t, with: .color(tick), lineWidth: 0.5)
                    }
                    ctx.draw(Text(labels[r]).font(.system(size: 10, weight: .bold)).foregroundColor(Brand.ink), at: CGPoint(x: 4, y: y(s)), anchor: .leading)
                    ctx.draw(Text(hm(totals[s] ?? 0)).font(.system(size: 11, weight: .bold)).monospacedDigit().foregroundColor(Brand.ink), at: CGPoint(x: size.width - 2, y: y(s)), anchor: .trailing)
                }
                var path = Path()
                for (i, g) in chart.segments.enumerated() {
                    let a = CGPoint(x: x(g.start), y: y(g.status)), b = CGPoint(x: x(g.end), y: y(g.status))
                    if i == 0 { path.move(to: a) } else { path.addLine(to: a) }
                    path.addLine(to: b)
                }
                ctx.stroke(path, with: .color(Brand.red), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                if chart.upto < chart.end && chart.upto > chart.start {
                    var now = Path(); now.move(to: CGPoint(x: x(chart.upto), y: top - 2)); now.addLine(to: CGPoint(x: x(chart.upto), y: top + row * 4 + 2))
                    ctx.stroke(now, with: .color(Color(red: 0.21, green: 0.52, blue: 0.73)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
                let foot = chart.upto < chart.end ? "So far today" : span != 86_400 ? "Daylight-saving day" : "Blank time = off duty"
                ctx.draw(Text(foot).font(.system(size: 9)).foregroundColor(Brand.muted), at: CGPoint(x: left, y: top + row * 4 + 9), anchor: .leading)
                ctx.draw(Text(hm(totals.values.reduce(0, +))).font(.system(size: 11, weight: .bold)).monospacedDigit().foregroundColor(Brand.darkRed),
                         at: CGPoint(x: size.width - 2, y: top + row * 4 + 9), anchor: .trailing)
            }
            .frame(height: top + row * 4 + 18)
            .contentShape(Rectangle())
            .onTapGesture { p in pick(p, chart: chart) }
            .background(GeometryReader { g in Color.clear.preference(key: ChartWidth.self, value: g.size.width) })
            .onPreferenceChange(ChartWidth.self) { width = $0 }
            .accessibilityElement()
            .accessibilityLabel("Duty status chart. " + Status.allCases.map { "\($0.rawValue) \(hm(totals[$0] ?? 0))" }.joined(separator: ", "))

            VStack(alignment: .leading, spacing: 0) {
                Text("Remarks").font(.subheadline.weight(.bold)).padding(.bottom, 4)
                if chart.remarks.isEmpty {
                    Text("No duty changes recorded. Each change will be listed here with its place.").font(.footnote).foregroundStyle(Brand.muted)
                }
                ForEach(chart.remarks, id: \.start) { g in
                    let e = g.entry!
                    remark(clock.time(g.start), Activity.of(e).label + (e.status == .driving && !e.to.isEmpty ? " to \(e.to)" : ""), e.from)
                }
                if let out = chart.clockOut, let end = out.end {
                    remark(clock.time(end), "Clock out", out.to.isEmpty ? out.from : out.to)
                }
            }
        }
    }

    private func remark(_ time: String, _ what: String, _ place: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(time).font(.footnote.weight(.bold)).monospacedDigit().frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(what).font(.footnote)
                Text(place.isEmpty ? "Place not entered" : Places.short(place)).font(.caption).foregroundStyle(Brand.muted)
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider() }
    }

    /// Tapping the chart opens the entry under the finger.
    private func pick(_ p: CGPoint, chart: Chart) {
        guard let onPick, width > left + right else { return }
        let w = width - left - right
        let f = (p.x - left) / w
        guard f >= 0, f <= 1 else { return }
        let t = chart.start.addingTimeInterval(Double(f) * chart.end.timeIntervalSince(chart.start))
        if let g = chart.segments.first(where: { $0.start <= t && t < $0.end }), let e = g.entry { onPick(e) }
    }

    private func hm(_ s: TimeInterval) -> String {
        let m = Int((s / 60).rounded())
        return "\(m / 60):\(String(format: "%02d", m % 60))"
    }
}

private struct ChartWidth: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: Places

/// Suggested places as chips, plus a typed city or address, with a Hotel switch.
struct PlaceField: View {
    let label: String
    let suggestions: [String]
    @Binding var place: String
    @State private var isHotel = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        var seen = Set<String>()
        let chips = suggestions.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(5)
        let matches = text.count >= 2 ? Cities.names.filter { $0.lowercased().hasPrefix(text.lowercased()) && $0 != text }.prefix(4) : []
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline.weight(.semibold))
            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Array(chips), id: \.self) { c in
                            Button(Places.short(c)) { place = c; text = ""; focused = false }
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14).frame(minHeight: 40)
                                .foregroundStyle(place == c ? Brand.darkRed : Brand.ink)
                                .background(place == c ? Color(red: 0.99, green: 0.96, blue: 0.96) : .white, in: Capsule())
                                .overlay(Capsule().stroke(place == c ? Brand.red : Color(white: 0.8)))
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                TextField(isHotel ? "Hotel city or address" : chips.isEmpty ? "City or address" : "Or type a city or address", text: $text)
                    .textInputAutocapitalization(.words).autocorrectionDisabled().focused($focused)
                    .padding(.horizontal, 12).frame(minHeight: 46)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(white: 0.8)))
                    .onChange(of: text) { _, _ in compose() }
                Toggle("Hotel", isOn: $isHotel).fixedSize().onChange(of: isHotel) { _, _ in if !text.isEmpty { compose() } }
            }
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
        .onAppear {
            if !place.isEmpty && !chips.contains(place) {
                isHotel = place.hasPrefix("Hotel – ")
                text = isHotel ? String(place.dropFirst("Hotel – ".count)) : place
            }
        }
    }

    private func compose() {
        let t = text.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { place = isHotel ? Places.hotel(t) : t }
    }
}

// MARK: One step

struct StepSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let step: Step
    @State private var time = Date()
    @State private var place = ""
    @State private var miles = ""
    @State private var error = ""
    @State private var ready = false

    var body: some View {
        let active = model.active
        let current = active.map(Activity.of)
        let ending = active?.status == .driving
        let estimate = ending ? Places.estimateMiles(active!.from, place) : nil
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Time").font(.subheadline.weight(.semibold))
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute).labelsHidden()
                            .environment(\.timeZone, model.log.profile.timeZone)
                    }
                    PlaceField(label: step == .clockOut ? "Where you finished" : step == .act(.pretrip) ? "Starting from" : ending ? "Where you stopped" : "Where you are",
                               suggestions: suggestions(), place: $place)
                    if ending {
                        TextField(estimate.map { "Leave blank to use \(milesText($0)) mi" } ?? "City not recognized: enter miles", text: $miles)
                            .keyboardType(.decimalPad)
                            .field("Miles for this drive\(estimate.map { " · estimate \(milesText($0))" } ?? "")")
                    }
                    if step == .act(.riding) { Note(text: "Riding in the passenger seat while your co-driver drives is logged as On duty.") }
                    if step == .act(.fuel) { Note(text: "Fueling is On duty under DOT rules. Use Quick break for a stop where you are off work.") }
                    if !error.isEmpty { Text(error).font(.subheadline).foregroundStyle(.red) }
                }
                .padding(20)
            }
            .navigationTitle(step.label(now: current))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.busy ? "Saving…" : "Save") { Task { await save(ending: ending, estimate: estimate) } }.disabled(model.busy)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            guard !ready else { return }
            ready = true
            if let a = model.active { place = a.status == .driving ? "" : a.from } else { place = suggestions().first ?? "" }
        }
    }

    private func suggestions() -> [String] {
        let clock = model.clock
        let t0 = clock.bounds(model.today).start
        let all = model.log.all
        let todays = all.filter { $0.start >= t0 }.flatMap { [$0.from, $0.to] }.filter { !$0.isEmpty }.reversed()
        guard model.active != nil else {
            // Where yesterday ended, if it was a hotel or somewhere other than the office.
            let before = t0
            let prev = model.log.entries.filter { e in e.end.map { $0 <= before && $0 > before.addingTimeInterval(-86_400) } ?? false }
                .max { $0.end! < $1.end! }
            let last = prev.map { $0.to.isEmpty ? $0.from : $0.to } ?? ""
            return [last.isEmpty || last == Places.preston ? "" : Places.hotel(last), Places.preston]
        }
        if step == .clockOut || step == .act(.posttrip) { return todays.filter { $0.hasPrefix("Hotel – ") } + [Places.preston] + todays }
        return Array(todays) + [Places.preston]
    }

    private func save(ending: Bool, estimate: Double?) async {
        error = ""
        let clock = model.clock
        let now = Date()
        var at = (try? clock.date(day: clock.dayKey(now), time: clock.hhmm(time))) ?? time
        if at > now.addingTimeInterval(60) { at = (try? clock.date(day: Clock.shift(clock.dayKey(now), by: -1), time: clock.hhmm(time))) ?? at }
        let trimmed = place.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { error = "Enter where you are. The log needs the city at every change."; return }
        var typed: Double?
        if !miles.isEmpty {
            guard let m = Double(miles.replacingOccurrences(of: ",", with: ".")), m >= 0 else { error = "Enter a valid distance."; return }
            typed = m
        } else if ending && estimate == nil {
            error = "We couldn’t estimate this drive from its places. Enter the miles."; return
        }
        do {
            try await model.take(step, at: at, place: trimmed, miles: typed)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: Fill in or fix a day

struct TimelineEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let day: String
    let ld: Bool

    struct Row: Identifiable, Equatable {
        var id = UUID().uuidString.lowercased()
        var time: String
        var step: Step
        var place: String
        var miles: String
    }

    @State private var date = ""
    @State private var rows: [Row] = []
    @State private var prior: [Entry] = []
    @State private var error = ""
    @State private var ready = false

    var body: some View {
        let clock = model.clock
        let editing = !prior.isEmpty
        let others = model.entries(startingOn: date)
        let built = build(clock)
        let lastAct: Activity? = { if let last = rows.last, case .act(let a) = last.step { return a }; return nil }()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if editing {
                        Text(Clock.label(date, "EEEE, MMMM d")).font(.headline)
                    } else {
                        DatePicker("Date", selection: Binding(get: { (try? clock.date(day: date, time: "12:00")) ?? Date() }, set: { date = clock.dayKey($0) }),
                                   displayedComponents: .date).font(.subheadline.weight(.semibold))
                    }
                    ForEach($rows) { $row in
                        let i = rows.firstIndex { $0.id == row.id } ?? 0
                        let next = i + 1 < rows.count ? rows[i + 1] : nil
                        let estimate = row.step == .act(.drive) ? next.flatMap { Places.estimateMiles(row.place, $0.place) } : nil
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TimeField(label: "Step \(i + 1)", value: $row.time)
                                Picker("Activity", selection: $row.step) {
                                    if i == 0 {
                                        Text("Clock in · pre-trip").tag(Step.act(.pretrip))
                                    } else {
                                        ForEach(Activity.allCases) { a in Text(a.label == a.status.rawValue ? a.label : "\(a.label) · \(a.status.rawValue)").tag(Step.act(a)) }
                                        Text("Clock out").tag(Step.clockOut)
                                    }
                                }
                                .pickerStyle(.menu)
                                if i > 0 {
                                    Button(role: .destructive) { rows.removeAll { $0.id == row.id } } label: { Image(systemName: "trash") }
                                        .accessibilityLabel("Remove step \(i + 1)")
                                }
                            }
                            CityField(label: "Place", placeholder: "City, address or hotel", text: $row.place)
                            if row.step == .act(.drive) {
                                TextField(estimate.map { "\(milesText($0)) mi estimated" } ?? "Miles", text: $row.miles).keyboardType(.decimalPad).field("Miles")
                            }
                        }
                        .padding(12)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.paperLine))
                    }
                    if let a = lastAct {
                        Text("Next step").font(.subheadline.weight(.semibold))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(nextSteps(a), id: \.self) { s in
                                    Button(s.label(now: a)) { add(s) }
                                        .font(.subheadline.weight(.semibold)).padding(.horizontal, 14).frame(minHeight: 40)
                                        .background(.white, in: Capsule()).overlay(Capsule().stroke(Color(white: 0.8)))
                                }
                            }
                        }
                    } else {
                        Text("Day ends at clock out. Remove it to add more steps.").font(.footnote).foregroundStyle(Brand.muted)
                    }
                    Text("Drive miles are estimated from the places on either side; type miles to override. A time earlier than the step before it is read as after midnight.")
                        .font(.footnote).foregroundStyle(Brand.muted)
                    switch built {
                    case .success(let entries): HosChartView(entries: entries, day: date)
                    case .failure(let e): Note(text: e.localizedDescription)
                    }
                    if !editing && !others.isEmpty {
                        Note(text: "This replaces the \(others.count) \(others.count == 1 ? "entry" : "entries") already logged on this date.")
                    }
                    if !error.isEmpty { Text(error).font(.subheadline).foregroundStyle(.red) }
                }
                .padding(20)
            }
            .navigationTitle(editing ? "Fix this day" : "Fill in a day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.busy ? "Saving…" : "Save day") { Task { await save(clock) } }
                        .disabled(model.busy || (try? built.get()) == nil)
                }
            }
        }
        .onAppear(perform: setUp)
    }

    private func setUp() {
        guard !ready else { return }
        ready = true
        date = day
        prior = model.entries(startingOn: day).filter { $0.end != nil }
        let clock = model.clock
        rows = prior.isEmpty
            ? [Row(time: "07:00", step: .act(.pretrip), place: Places.preston, miles: "")]
            : toSteps(prior).map { Row(id: $0.id, time: clock.hhmm($0.time), step: $0.step, place: $0.place, miles: $0.miles.map(milesText) ?? "") }
    }

    private func add(_ s: Step) {
        guard let last = rows.last else { return }
        let parts = last.time.split(separator: ":").compactMap { Int($0) }
        let m = parts.count == 2 ? (parts[0] * 60 + parts[1] + 30) % 1440 : 480
        let keep: Bool = { if case .act(let a) = last.step { return a != .drive && a != .riding }; return true }()
        rows.append(Row(time: String(format: "%02d:%02d", m / 60, m % 60), step: s, place: keep ? last.place : "", miles: ""))
    }

    private func build(_ clock: Clock) -> Result<[Entry], Error> {
        Result {
            var steps: [TimelineStep] = []
            for r in rows {
                let t = try clock.stepTime(day: date, r.time, after: steps.last?.time)
                let m = r.miles.isEmpty ? nil : Double(r.miles.replacingOccurrences(of: ",", with: "."))
                steps.append(TimelineStep(id: r.id, time: t, step: r.step, place: r.place, miles: m))
            }
            let tag = ld || (prior.sorted { $0.start < $1.start }.first?.note.contains(Places.ldMark) ?? false) ? Places.ldMark : ""
            return try toEntries(steps, tag: tag)
        }
    }

    private func save(_ clock: Clock) async {
        error = ""
        do {
            if let blank = rows.firstIndex(where: { $0.place.trimmingCharacters(in: .whitespaces).isEmpty }) {
                throw LogError("Step \(blank + 1) needs a place. The log needs the city at every change.")
            }
            let entries = try build(clock).get()
            if let d = entries.first(where: { $0.status == .driving && $0.miles == nil }) {
                throw LogError("Couldn’t estimate the drive from “\(d.from)” to “\(d.to)”. Enter its miles.")
            }
            try await model.saveSimpleDay(entries, date: date, replace: !prior.isEmpty || !model.entries(startingOn: date).isEmpty)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: Inspection view

/// Today and the previous 7 days, the way an officer asks to see them, with the header details.
struct InspectionView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let p = model.log.profile
        let all = model.log.all
        let clock = model.clock
        let c = HosClocks(entries: all, now: model.now)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 10) {
                        detail("Driver", p.name.isEmpty ? "Not set" : p.name)
                        detail("Co-driver", p.coDriver.isEmpty ? "None" : p.coDriver)
                        detail("Carrier", p.carrier)
                        detail("Truck / trailer", p.vehicle.isEmpty ? "Not set" : p.vehicle)
                        detail("Main office", p.office.isEmpty ? "Not set" : p.office)
                        detail("Home terminal", p.terminal.isEmpty ? "Not set" : p.terminal)
                        detail("24-hour period starts", "Midnight, \(p.zone.replacingOccurrences(of: "_", with: " "))")
                        detail("On duty, last 8 days", "\(duration(70 * 3600 - c.cycle)) of 70h")
                    }
                    ForEach(0..<8, id: \.self) { back in
                        let d = Clock.shift(model.today, by: -back)
                        let (s, e) = clock.bounds(d)
                        let miles = all.filter { $0.status == .driving && $0.start >= s && $0.start < e }.reduce(0) { $0 + ($1.miles ?? 0) }
                        let any = all.contains { $0.start < e && ($0.end ?? model.now) > s }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(Clock.label(d, "EEEE, MMMM d, yyyy")).font(.headline)
                                Spacer()
                                Text(any ? "\(milesText(miles)) mi driving" : "Off duty all day").font(.footnote).foregroundStyle(Brand.muted)
                            }
                            HosChartView(entries: all, day: d)
                        }
                        .padding(.top, 8)
                    }
                    Text("I certify these entries are true and correct. Driver’s signature: ____________________").font(.footnote).foregroundStyle(Brand.muted)
                }
                .padding(20)
            }
            .navigationTitle("Record of duty status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(Brand.muted)
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(Brand.ink)
        }
    }
}
#endif
