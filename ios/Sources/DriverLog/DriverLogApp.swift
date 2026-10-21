#if os(iOS)
import DriverLogCore
import SwiftUI

/// Launch options used by CI screenshots: `-demo off|clocked|driving` and `-screen daily|history|simple|settings`.
enum LaunchOptions {
    static var demo: String? { UserDefaults.standard.string(forKey: "demo") }
    static var screen: String? { UserDefaults.standard.string(forKey: "screen") }
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
            // Save drive progress when leaving the app; refresh when coming back.
            if phase == .background { Task { await model.flush() } }
            if phase == .active, model.phase == .signedIn, !model.driving { Task { await model.load() } }
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
                        .tabItem { Label("Log", systemImage: "list.clipboard") }
                        .tag(AppModel.Tab.log)
                    HistoryScreen()
                        .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                        .tag(AppModel.Tab.history)
                }
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
        .onAppear { if LaunchOptions.screen == "history" { model.tab = .history } }
    }
}
#endif
