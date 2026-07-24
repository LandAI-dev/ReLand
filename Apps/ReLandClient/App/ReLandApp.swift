import SwiftUI

@main
struct ReLandApp: App {
    @State private var model = ClientAppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .tint(ReLandTheme.accent)
        }
    }
}

private struct RootView: View {
    @Bindable var model: ClientAppModel

    var body: some View {
        Group {
            if !model.hasCompletedOnboarding {
                OnboardingView(model: model)
            } else if model.isRemoteSessionPresented {
                RemoteSessionView(model: model)
            } else {
                DeviceListView(model: model)
            }
        }
        .alert(
            "ReLand",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        model.alertMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                model.alertMessage = nil
            }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }
}
