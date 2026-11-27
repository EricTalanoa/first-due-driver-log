#if os(iOS)
import DriverLogCore
import SwiftUI

/// Launch options used by CI screenshots: `-demo off|ld`, `-screen daily|ld|inspect|step|timeline|history|simple|settings`, `-tutorial show|tip`.
enum LaunchOptions {
    static var demo: String? { UserDefaults.standard.string(forKey: "demo") }
    static var screen: String? { UserDefaults.standard.string(forKey: "screen") }
    /// `-tutorial show` (the cards, as on first launch) or `-tutorial tip` (the first tooltip).
    static var tutorial: String? { UserDefaults.standard.string(forKey: "tutorial") }
}

@main
struct DriverLogApp: App {
    @StateObject private var model = AppModel(backend: LaunchOptions.demo.map { DemoBackend(state: $0) } ?? SupabaseBackend())
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(Brand.red)
                .task { await model.start() }
                .onOpenURL { model.backend.handle($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Refresh when coming back, so entries made on the website show up.
            if phase == .active, model.phase == .signedIn, !model.busy { Task { await model.load() } }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            switch model.phase {
            case .checking:
                ZStack { Brand.page.ignoresSafeArea(); ProgressView() }
            case .signedOut:
                SignInView()
            case .signedIn:
                TabView(selection: $model.tab) {
                    LogScreen()
                        .tabItem { Label("Today", systemImage: "calendar") }
                        .tag(AppModel.Tab.today)
                    LdScreen()
                        .tabItem { Label("LD", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                        .tag(AppModel.Tab.ld)
                    HistoryScreen()
                        .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                        .tag(AppModel.Tab.history)
                }
                .fullScreenCover(isPresented: $model.tutorialCards) { TutorialCards() }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(Brand.card, in: RoundedRectangle(cornerRadius: 10))
                    .shadow(radius: 8, y: 4)
                    .padding(.bottom, 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.toast)
        .onAppear {
            if LaunchOptions.screen == "history" { model.tab = .history }
            if ["ld", "inspect", "step"].contains(LaunchOptions.screen ?? "") { model.tab = .ld }
        }
    }
}
#endif
