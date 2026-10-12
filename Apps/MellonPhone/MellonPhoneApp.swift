import SwiftUI

@main
struct MellonPhoneApp: App {
    @State private var model = PhoneModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
                .onOpenURL { model.handle(url: $0) }
                .onChange(of: scenePhase) { _, phase in
                    model.setActive(phase == .active)
                }
        }
    }
}

struct RootView: View {
    @Bindable var model: PhoneModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch model.phase {
            case .unpaired:
                OnboardingView(model: model)
            case let .pairing(macName, code):
                PairingProgressView(macName: macName, code: code) { model.cancelPairing() }
            case .connecting, .connected:
                ControlView(model: model)
            }
        }
        .animation(.smooth, value: model.phase)
        .alert("Mellon", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
