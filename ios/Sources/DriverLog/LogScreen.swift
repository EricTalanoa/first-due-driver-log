#if os(iOS)
import DriverLogCore
import SwiftUI

/// Sheets the Today, LD and History screens can open.
enum Sheet: Identifiable {
    case simple, ld, edit(Entry), settings, timeline(String, ld: Bool), inspect, step(Step)
    var id: String {
        switch self {
        case .simple: return "simple"
        case .ld: return "ld"
        case .edit(let e): return "edit-\(e.id)"
        case .settings: return "settings"
        case .timeline(let d, let ld): return "timeline-\(d)-\(ld)"
        case .inspect: return "inspect"
        case .step(let s): return "step-\(s)"
        }
    }

    @MainActor @ViewBuilder
    func view(_ model: AppModel) -> some View {
        let fallback = model.day.isEmpty ? model.today : model.day
        switch self {
        case .simple: SimpleDayEditor(day: fallback)
        case .ld: LdDayEditor(day: fallback)
        case .edit(let e): EntryEditor(entry: e)
        case .settings: SettingsView()
        case .timeline(let d, let ld): TimelineEditor(day: d, ld: ld)
        case .inspect: InspectionView()
        case .step(let s): StepSheet(step: s)
        }
    }
}

/// The Today tab: Add entry, then the selected day's DOT chart, totals and entries.
struct LogScreen: View {
    @EnvironmentObject var model: AppModel
    @State private var sheet: Sheet?
    @State private var choosing = false
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        BrandTitle()
                        Spacer()
                        Button { sheet = .settings } label: {
                            Image(systemName: "gearshape").font(.title2).foregroundStyle(Brand.ink).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Driver and vehicle settings")
                    }
                    if let error = model.error { ErrorBanner(text: error) { Task { await model.load() } } }
                    Button { choosing = true } label: {
                        Label("Add entry", systemImage: "plus").font(.headline).foregroundStyle(Brand.darkRed)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Brand.red.opacity(0.45), style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                    }
                    .disabled(!model.loaded)
                    DailyLog(sheet: $sheet, confirmClear: $confirmClear)
                }
                .padding(16)
            }
            .background(Brand.page.ignoresSafeArea())
            .refreshable { await model.refresh() }
            .toolbar(.hidden, for: .navigationBar)
        }
        .confirmationDialog("Add to your log", isPresented: $choosing, titleVisibility: .visible) {
            Button("Simple day") { sheet = .simple }
            Button("Fill in a day step by step") { sheet = .timeline(model.day.isEmpty ? model.today : model.day, ld: false) }
            Button("Advanced entry") { sheet = .edit(newManualEntry()) }
        } message: {
            Text("Simple day is for local jobs: cities, clock times and lunch, and the chart is estimated. Step by step lists each drive, stop and break with its time and place. Advanced adds one duty period.")
        }
        .alert("Clear this day?", isPresented: $confirmClear) {
            Button("Clear day", role: .destructive) { Task { try? await model.clear(day: model.day) } }
        } message: {
            Text("This deletes all \(model.entries(startingOn: model.day).count) entries that start on \(Clock.label(model.day, "EEEE, MMMM d")). Anything you are recording now is kept.")
        }
        .sheet(item: $sheet) { $0.view(model) }
        .onAppear {
            switch LaunchOptions.screen {
            case "simple": sheet = .simple
            case "settings": sheet = .settings
            case "timeline": sheet = .timeline(Clock.shift(model.today, by: -1), ld: false)
            default: break
            }
        }
    }

    private func newManualEntry() -> Entry {
        let clock = model.clock
        let end = model.day.isEmpty || model.day == model.today ? Date() : ((try? clock.date(day: model.day, time: "10:00")) ?? Date())
        return Entry(status: .driving, start: end.addingTimeInterval(-3600), end: end)
    }
}

struct BrandTitle: View {
    var body: some View {
        HStack(spacing: 8) {
            if let logo = BrandHeader.logo { Image(uiImage: logo).resizable().scaledToFit().frame(height: 44) }
            VStack(alignment: .leading, spacing: 1) {
                Text("FIRST DUE MOVERS").font(.system(size: 11, weight: .bold)).tracking(1.4).foregroundStyle(Brand.red)
                Text("Driver’s log").font(.title2.weight(.bold)).foregroundStyle(Brand.ink)
            }
        }
    }
}

struct ErrorBanner: View {
    let text: String
    let retry: () -> Void
    var body: some View {
        HStack(alignment: .top) {
            Text(text).font(.subheadline).foregroundStyle(Color(red: 0.55, green: 0.12, blue: 0.1))
            Spacer()
            Button("Reload", action: retry).font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .background(Color(red: 0.99, green: 0.93, blue: 0.92), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: Daily log

struct DailyLog: View {
    @EnvironmentObject var model: AppModel
    @Binding var sheet: Sheet?
    @Binding var confirmClear: Bool

    var body: some View {
        let day = model.day.isEmpty ? model.today : model.day
        let view = DayView(log: model.log, day: day, now: model.now)
        let zone = model.log.profile.timeZone
        let started = model.entries(startingOn: day)
        let editable: Sheet? = readSimpleDay(started, zone: zone) != nil ? .simple
            : readLdDay(started, zone: zone) != nil ? .ld
            : !started.isEmpty && !started.contains { $0.id == model.active?.id } ? .timeline(day, ld: false) : nil
        Paper {
            Text(day == model.today ? "Today" : "Daily log").font(.title2.weight(.bold)).foregroundStyle(Brand.ink)
            HStack {
                Button { model.day = Clock.shift(day, by: -1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous day")
                DatePicker("Log date", selection: dateBinding(day), displayedComponents: .date).labelsHidden()
                Button { model.day = Clock.shift(day, by: 1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next day")
                Spacer()
                if let editable {
                    Button { sheet = editable } label: { Label("Edit day", systemImage: "pencil") }.buttonStyle(OutlineButtonStyle())
                }
            }
            .font(.title3)
            Text("\(model.log.profile.name.isEmpty ? "Driver name not set" : model.log.profile.name) · \(model.log.profile.vehicle.isEmpty ? "Vehicle not set" : "Truck \(model.log.profile.vehicle)")")
                .font(.footnote).foregroundStyle(Brand.muted)
            Divider()
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                Stat(label: "Driving", value: duration(view.totals[.driving] ?? 0))
                Stat(label: "On duty, not driving", value: duration(view.totals[.onDuty] ?? 0))
                Stat(label: "Off duty + sleeper", value: duration((view.totals[.offDuty] ?? 0) + (view.totals[.sleeper] ?? 0)))
                Stat(label: "Completed-trip miles", value: "\(milesText(view.miles)) mi\(view.needsCheck ? " · check" : "")")
            }
            Divider()
            HosChartView(entries: model.log.all, day: day) { e in if e.id != model.active?.id { sheet = .edit(e) } }
            Divider()
            HStack {
                Text("Duty periods & trips").font(.headline).foregroundStyle(Brand.ink)
                Spacer()
                Button(role: .destructive) { confirmClear = true } label: { Label("Clear day", systemImage: "trash") }
                    .font(.footnote.weight(.semibold))
                    .disabled(model.busy || started.isEmpty)
            }
            if view.rows.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "truck.box").font(.title).foregroundStyle(Brand.muted)
                    Text("No entries for this day").font(.headline)
                    Text("Use Add entry for a local day, or the LD tab on a long-distance day.").font(.footnote).foregroundStyle(Brand.muted).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                ForEach(view.rows) { e in
                    EntryCard(entry: e, day: day) { sheet = .edit(e) }
                }
            }
        }
    }

    private func dateBinding(_ day: String) -> Binding<Date> {
        let clock = model.clock
        return Binding(
            get: { (try? clock.date(day: day, time: "12:00")) ?? Date() },
            set: { model.day = clock.dayKey($0) }
        )
    }
}

struct Stat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(Brand.muted)
            Text(value).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(Brand.ink)
        }
    }
}

struct EntryCard: View {
    @EnvironmentObject var model: AppModel
    let entry: Entry
    let day: String
    let edit: () -> Void

    var body: some View {
        let clock = model.clock
        let isActive = entry.id == model.active?.id
        let (start, end) = clock.bounds(day)
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(Brand.color(for: entry.status)).frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.status.rawValue).font(.headline)
                    Spacer()
                    Text(isActive ? "Recording now" : duration(min(entry.end ?? model.now, end).timeIntervalSince(max(entry.start, start))))
                        .font(.footnote).foregroundStyle(Brand.muted)
                }
                Text("\(clock.time(entry.start)) – \(isActive ? "now" : clock.time(entry.end!))\(entry.start < start || (entry.end ?? model.now) > end ? " · spans days" : "")")
                    .font(.subheadline).foregroundStyle(Brand.muted)
                if !entry.from.isEmpty || !entry.to.isEmpty {
                    Label(entry.status == .driving || !entry.to.isEmpty ? "\(entry.from.isEmpty ? "Start not entered" : entry.from) → \(entry.to.isEmpty ? "Destination not entered" : entry.to)" : entry.from,
                          systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(Brand.ink)
                }
                if entry.status == .driving && !isActive {
                    Text(entry.miles.map { "\(milesText($0)) mi" } ?? "Distance needed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(entry.miles == nil || entry.partial ? Brand.warn : Brand.ink)
                    + Text(entry.partial ? " · check distance" : "").font(.subheadline).foregroundColor(Brand.warn)
                }
                if !entry.note.isEmpty { Text(entry.note.replacingOccurrences(of: Places.ldMark, with: "")).font(.footnote).foregroundStyle(Brand.muted) }
            }
            if !isActive {
                Button(action: edit) { Image(systemName: "pencil").font(.body.weight(.semibold)) }
                    .accessibilityLabel("Edit \(entry.status.rawValue) entry at \(clock.time(entry.start))")
            }
        }
        .padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
