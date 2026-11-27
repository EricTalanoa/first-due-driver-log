#if os(iOS)
import DriverLogCore
import SwiftUI

// First-launch tutorial: a few swipe cards, then tooltips that point at the real buttons one at a time.
// Seen once per account (stored with the account, so a new phone doesn't show it again); replay it from
// Settings or the ? on the LD tab. The dimmed layer swallows taps, so nothing in the log changes during it.

enum TutorialTip: Int, CaseIterable {
    case addEntry, chart, steps, hours, inspect

    var tab: AppModel.Tab {
        switch self {
        case .addEntry, .chart: return .today
        case .steps, .hours, .inspect: return .ld
        }
    }

    /// The id of the view this tip points at (see `tutorialAnchor`).
    var anchor: String {
        switch self {
        case .addEntry: return "addEntry"
        case .chart: return "todayChart"
        case .steps: return "ldSteps"
        case .hours: return "ldChart"
        case .inspect: return "ldInspect"
        }
    }

    var title: String {
        switch self {
        case .addEntry: return "Local day? Start here"
        case .chart: return "Your day, the way an officer reads it"
        case .steps: return "LD day: tap what you're doing"
        case .hours: return "Your hours"
        case .inspect: return "Pulled over or inspected?"
        }
    }

    var text: String {
        switch self {
        case .addEntry: return "Add entry → Simple day: enter the cities, clock times and lunch, and the whole chart is filled in for you."
        case .chart: return "Off duty, sleeper, driving and on duty across 24 hours, with totals and the place of every change. Tap a line to fix that entry."
        case .steps: return "Clock in, Start driving, Fuel stop, Lunch, Start unload… Each tap asks for the time and the place. Rounding up a few minutes is fine."
        case .hours: return "Once you clock in, the clocks above the chart show what's left: 11 hours driving, the 14-hour window, the 30-minute break and the 70-hour week."
        case .inspect: return "Open Inspection view: today and the last 7 days with your details, ready to hand over."
        }
    }
}

/// Positions of the views tutorial tips point at, by id.
struct TutorialAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Marks a view a tutorial tip can point at. Also gives it a scroll id with the same name.
    func tutorialAnchor(_ id: String) -> some View {
        self.id(id).anchorPreference(key: TutorialAnchorKey.self, value: .bounds) { [id: $0] }
    }

    /// Draws the current tip over this screen when the tip belongs to `tab`.
    func tutorialOverlay(_ tab: AppModel.Tab) -> some View {
        overlayPreferenceValue(TutorialAnchorKey.self) { anchors in TutorialOverlay(anchors: anchors, tab: tab) }
    }
}

struct TutorialOverlay: View {
    @EnvironmentObject var model: AppModel
    let anchors: [String: Anchor<CGRect>]
    let tab: AppModel.Tab

    var body: some View {
        GeometryReader { geo in
            if let tip = model.tutorialTip, tip.tab == tab {
                let hole = anchors[tip.anchor].map { geo[$0].insetBy(dx: -8, dy: -8) }
                ZStack(alignment: .topLeading) {
                    Path { p in
                        p.addRect(CGRect(origin: CGPoint(x: -geo.size.width, y: -geo.size.height), size: CGSize(width: geo.size.width * 3, height: geo.size.height * 3)))
                        if let hole { p.addRoundedRect(in: hole, cornerSize: CGSize(width: 14, height: 14)) }
                    }
                    .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    if let hole {
                        RoundedRectangle(cornerRadius: 14).stroke(Brand.brightRed, lineWidth: 3)
                            .frame(width: hole.width, height: hole.height)
                            .position(x: hole.midX, y: hole.midY)
                            .allowsHitTesting(false)
                    }
                    bubble(tip)
                        .frame(width: min(geo.size.width - 32, 380))
                        .position(x: geo.size.width / 2, y: bubbleCenter(hole, height: geo.size.height))
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.tutorialTip)
    }

    /// Below the highlighted view when there's room, otherwise above it.
    private func bubbleCenter(_ hole: CGRect?, height: CGFloat) -> CGFloat {
        let half: CGFloat = 105
        guard let hole else { return height / 2 }
        if hole.maxY + 12 + half * 2 < height { return hole.maxY + 12 + half }
        if hole.minY - 12 - half * 2 > 0 { return hole.minY - 12 - half }
        return height - half - 12
    }

    private func bubble(_ tip: TutorialTip) -> some View {
        let count = TutorialTip.allCases.count
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(tip.rawValue + 1) of \(count)").font(.caption.weight(.semibold)).foregroundStyle(Brand.muted)
            Text(tip.title).font(.headline).foregroundStyle(Brand.ink)
            Text(tip.text).font(.subheadline).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Skip") { model.finishTutorial() }.foregroundStyle(Brand.muted)
                Spacer()
                if tip.rawValue > 0 {
                    Button("Back") { model.showTip(TutorialTip(rawValue: tip.rawValue - 1)!) }.buttonStyle(OutlineButtonStyle())
                }
                Button(tip.rawValue == count - 1 ? "Done" : "Next") { model.nextTip() }
                    .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(minHeight: 44)
                    .background(Brand.red, in: RoundedRectangle(cornerRadius: 10))
            }
            .font(.subheadline.weight(.semibold))
            .padding(.top, 4)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
    }
}

// MARK: Cards

private struct Card: Identifiable {
    let id: Int
    let icon: String
    let title: String
    let text: String
}

private let cards = [
    Card(id: 0, icon: "truck.box.fill", title: "Welcome to Driver Log",
         text: "Your hours and miles, kept the way a DOT officer reads them. A minute a day keeps you ready for an inspection."),
    Card(id: 1, icon: "square.split.3x1", title: "Three tabs",
         text: "Today: local days and the day's chart.\nLD: long-distance days, one tap at a time.\nHistory: every day, with LD trips outlined in red."),
    Card(id: 2, icon: "hand.tap.fill", title: "LD days: tap what you're doing",
         text: "Clock in, Start driving, Fuel stop, Lunch, Start unload, Clock out. Each tap asks for the time and the place, and the chart draws itself."),
    Card(id: 3, icon: "chart.xyaxis.line", title: "The chart and your hours",
         text: "The chart shows off duty, sleeper, driving and on duty across the day. The clocks show what's left of your 11 hours driving, 14-hour window, 30-minute break and 70-hour week."),
    Card(id: 4, icon: "checkmark.shield.fill", title: "Pulled over?",
         text: "Open Inspection view on the LD tab: today and the previous 7 days with your details, ready to show the officer."),
]

struct TutorialCards: View {
    @EnvironmentObject var model: AppModel
    @State private var page = 0

    var body: some View {
        let last = page == cards.count - 1
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { model.finishTutorial() }.font(.body.weight(.semibold)).foregroundStyle(Brand.muted).opacity(last ? 0 : 1)
            }
            .padding(.horizontal, 20).padding(.top, 12)
            TabView(selection: $page) {
                ForEach(cards) { c in
                    VStack(spacing: 22) {
                        Spacer()
                        Image(systemName: c.icon).font(.system(size: 64, weight: .semibold)).foregroundStyle(Brand.red)
                            .frame(width: 120, height: 120).background(Color(red: 0.99, green: 0.95, blue: 0.95), in: Circle())
                        Text(c.title).font(.title.weight(.bold)).foregroundStyle(Brand.ink).multilineTextAlignment(.center)
                        Text(c.text).font(.body).foregroundStyle(Brand.muted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Spacer()
                    }
                    .padding(.horizontal, 32)
                    .tag(c.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            VStack(spacing: 10) {
                Button(last ? "Show me around" : "Next") {
                    if last { model.startTips() } else { withAnimation { page += 1 } }
                }
                .buttonStyle(PrimaryButtonStyle())
                if last {
                    Button("I'm all set") { model.finishTutorial() }.font(.body.weight(.semibold)).foregroundStyle(Brand.darkRed).frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 16)
        }
        .background(Brand.page.ignoresSafeArea())
    }
}
#endif
