#if os(iOS)
import DriverLogCore
import SwiftUI

/// Sheets the Log and History screens can open.
enum Sheet: Identifiable {
    case simple, edit(Entry), settings
    var id: String {
        switch self {
        case .simple: return "simple"
        case .edit(let e): return "edit-\(e.id)"
        case .settings: return "settings"
        }
    }
}

struct LogScreen: View {
    @EnvironmentObject var model: AppModel
    @State private var sheet: Sheet?
    @State private var choosing = false
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let error = model.error { ErrorBanner(text: error) { Task { await model.load() } } }
                    Button { choosing = true } label: {
                        Label("Add entry", systemImage: "plus").font(.headline).foregroundStyle(Brand.darkRed)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Brand.red.opacity(0.45), style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                    }
                    .disabled(!model.loaded)
                    DriveCard(review: { sheet = .edit($0) })
                    StatusPanel()
                    DailyLog(sheet: $sheet, confirmClear: $confirmClear, choosing: $choosing)
                }
                .padding(16)
            }
            .background(Brand.page.ignoresSafeArea())
            .refreshable { await model.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { BrandTitle() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { sheet = .settings } label: { Image(systemName: "gearshape") }.accessibilityLabel("Driver and vehicle settings")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .confirmationDialog("Add to your log", isPresented: $choosing, titleVisibility: .visible) {
            Button("Simple day") { sheet = .simple }
            Button("Advanced entry") { sheet = .edit(newManualEntry()) }
        } message: {
            Text("Simple day fills in the whole day from your office, cities, clock times and lunch. Advanced adds one duty period with exact times.")
        }
        .alert("Clear this day?", isPresented: $confirmClear) {
            Button("Clear day", role: .destructive) { Task { try? await model.clear(day: model.day) } }
        } message: {
            Text("This deletes all \(model.entries(startingOn: model.day).count) entries that start on \(Clock.label(model.day, "EEEE, MMMM d")). A drive you are recording now is kept.")
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .simple: SimpleDayEditor(day: model.day.isEmpty ? model.today : model.day)
            case .edit(let e): EntryEditor(entry: e)
            case .settings: SettingsView()
            }
        }
        .onAppear {
            switch LaunchOptions.screen {
            case "simple": sheet = .simple
            case "settings": sheet = .settings
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
            if let logo = BrandHeader.logo { Image(uiImage: logo).resizable().scaledToFit().frame(height: 30) }
            VStack(alignment: .leading, spacing: 0) {
                Text("FIRST DUE MOVERS").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(Brand.red)
                Text("Driver’s log").font(.headline).foregroundStyle(Brand.ink)
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

// MARK: Drive card

struct DriveCard: View {
    @EnvironmentObject var model: AppModel
    let review: (Entry) -> Void

    var body: some View {
        let active = model.active
        let driving = model.driving
        let day = DayView(log: model.log, day: model.today, now: model.now)
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Eyebrow(driving ? "Drive in progress" : model.onClock ? "On the clock" : "Off the clock", color: .white)
                Spacer()
                Text(active?.status.rawValue ?? "Not recording").font(.caption).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5).overlay(Capsule().stroke(Brand.cardLine))
            }
            HStack(spacing: 10) {
                ClockButton(title: active != nil && !model.onClock ? "Back on duty" : "Clock in", icon: "arrow.right.to.line", primary: !model.onClock) {
                    Task { await model.setStatus(.onDuty) }
                }
                .disabled(!model.loaded || model.busy || model.onClock)
                ClockButton(title: "Clock out", icon: "rectangle.portrait.and.arrow.right", primary: false) {
                    Task { await model.clockOut() }
                }
                .disabled(!model.loaded || model.busy || active == nil || driving)
            }
            HStack(alignment: .top) {
                Metric(label: driving ? "Drive time" : "Worked today",
                       value: driving ? duration(model.now.timeIntervalSince(active!.start)) : duration((day.totals[.onDuty] ?? 0) + (day.totals[.driving] ?? 0)))
                Spacer()
                Metric(label: driving ? "GPS miles · estimate" : "Miles today",
                       value: driving ? milesText(model.meter?.miles ?? active?.miles ?? 0) : milesText(day.miles), unit: "mi")
            }
            if !driving, let clockedIn = clockedInAt(day) {
                Text("Clocked in at \(model.clock.time(clockedIn))").font(.footnote).foregroundStyle(Brand.onDark)
            }
            Button {
                Task {
                    if let ended = await model.setStatus(driving ? .onDuty : .driving) { review(ended) }
                }
            } label: {
                Label(driving ? "End driving" : "Start driving", systemImage: driving ? "stop.fill" : "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!model.loaded || model.busy)
            if driving {
                Label(model.gpsMessage, systemImage: "location.fill").font(.footnote).foregroundStyle(Brand.onDark)
                    .frame(maxWidth: .infinity)
            } else if active != nil {
                Text("Clock out stops recording for the day.").font(.footnote).foregroundStyle(Brand.onDark).frame(maxWidth: .infinity)
            }
        }
        .padding(22)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .top) { UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16).fill(Brand.brightRed).frame(height: 5) }
    }

    private func clockedInAt(_ day: DayView) -> Date? {
        guard model.active != nil else { return nil }
        return day.rows.filter(\.isWork).map(\.start).min()
    }
}

struct ClockButton: View {
    let title: String
    let icon: String
    let primary: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(primary && enabled ? Brand.card : .white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(primary && enabled ? Color.white : Brand.cardRaised, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(primary && enabled ? .clear : Brand.cardLine))
                .opacity(enabled ? 1 : 0.4)
        }
    }
}

struct Metric: View {
    let label: String
    let value: String
    var unit: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.footnote).foregroundStyle(Brand.onDark)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 30, weight: .bold)).monospacedDigit().foregroundStyle(.white)
                if let unit { Text(unit).foregroundStyle(.white) }
            }
        }
    }
}

// MARK: Set status

struct StatusPanel: View {
    @EnvironmentObject var model: AppModel
    private let choices: [Status] = [.onDuty, .offDuty, .sleeper]

    private func detail(_ s: Status) -> String {
        switch s {
        case .onDuty: return "Loading, unloading, other work"
        case .offDuty: return "Break or finished for the day"
        default: return "Resting in the sleeper"
        }
    }

    var body: some View {
        Paper {
            Text("Set status").font(.title2.weight(.bold)).foregroundStyle(Brand.ink)
            ForEach(choices) { status in
                let selected = model.active?.status == status
                Button { Task { await model.setStatus(status) } } label: {
                    HStack(spacing: 14) {
                        Image(systemName: Brand.icon(for: status)).font(.title3).frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(status.rawValue).font(.headline)
                            Text(detail(status)).font(.footnote).foregroundStyle(Brand.muted)
                        }
                        Spacer()
                        if selected { Circle().fill(Brand.red).frame(width: 8, height: 8) }
                    }
                    .foregroundStyle(selected ? Brand.darkRed : Brand.ink)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selected ? Color(red: 0.99, green: 0.94, blue: 0.94) : .white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Brand.red : Brand.paperLine))
                }
                .disabled(!model.loaded || model.busy || model.driving)
            }
            if model.driving {
                Text("End your drive to change duty status.").font(.footnote).foregroundStyle(Brand.muted)
            }
        }
    }
}

// MARK: Daily log

struct DailyLog: View {
    @EnvironmentObject var model: AppModel
    @Binding var sheet: Sheet?
    @Binding var confirmClear: Bool
    @Binding var choosing: Bool

    var body: some View {
        let day = model.day.isEmpty ? model.today : model.day
        let view = DayView(log: model.log, day: day, now: model.now)
        let editable = readSimpleDay(model.entries(startingOn: day), zone: model.log.profile.timeZone) != nil
        Paper {
            Text("Daily log").font(.title2.weight(.bold)).foregroundStyle(Brand.ink)
            HStack {
                Button { model.day = Clock.shift(day, by: -1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous day")
                DatePicker("Log date", selection: dateBinding(day), displayedComponents: .date).labelsHidden()
                Button { model.day = Clock.shift(day, by: 1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next day")
                Spacer()
                if editable {
                    Button { sheet = .simple } label: { Label("Edit day", systemImage: "pencil") }.buttonStyle(OutlineButtonStyle())
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
            HStack {
                Text("Duty periods & trips").font(.headline).foregroundStyle(Brand.ink)
                Spacer()
                Button(role: .destructive) { confirmClear = true } label: { Label("Clear day", systemImage: "trash") }
                    .font(.footnote.weight(.semibold))
                    .disabled(model.busy || model.entries(startingOn: day).isEmpty)
            }
            if view.rows.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "truck.box").font(.title).foregroundStyle(Brand.muted)
                    Text("No entries for this day").font(.headline)
                    Text("Start recording above, or add a past trip.").font(.footnote).foregroundStyle(Brand.muted)
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
                if entry.status == .driving {
                    Text(entry.miles.map { "\(milesText($0)) mi\(entry.source == .gps ? " · GPS estimate" : "")" } ?? "Distance needed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(entry.miles == nil || entry.partial ? Brand.warn : Brand.ink)
                    + Text(entry.partial ? " · check distance" : "").font(.subheadline).foregroundColor(Brand.warn)
                }
                if !entry.note.isEmpty { Text(entry.note).font(.footnote).foregroundStyle(Brand.muted) }
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
