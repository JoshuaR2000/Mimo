import SwiftUI

@main
struct MimoApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView(app: app)
        }
        #if os(macOS)
        .defaultSize(width: 520, height: 860)
        #endif
    }
}

struct RootView: View {
    let app: AppState

    var body: some View {
        if app.onboarded {
            MainView(app: app)
        } else {
            OnboardingView(app: app)
        }
    }
}
