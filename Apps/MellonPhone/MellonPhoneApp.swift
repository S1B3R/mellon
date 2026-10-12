import MellonCore
import SwiftUI

@main
struct MellonPhoneApp: App {
    @State private var model = PhoneModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
                .onOpenURL { model.handleLink($0) }
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
        .confirmationDialog(
            "Parear com um Mac?",
            isPresented: Binding(
                get: { model.pendingInvitation != nil },
                set: { if !$0 { model.dismissPendingInvitation() } }
            ),
            titleVisibility: .visible,
            presenting: model.pendingInvitation
        ) { _ in
            Button("Parear") { model.confirmPendingInvitation() }
            Button("Cancelar", role: .cancel) { model.dismissPendingInvitation() }
        } message: { invitation in
            Text(pendingInvitationMessage(invitation))
        }
        .alert("Mellon", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func pendingInvitationMessage(_ invitation: PairingInvitation) -> String {
        var message = "Um link pediu para parear este iPhone com “\(invitation.macName)”. "
            + "Só continue se você acabou de gerar este código no seu Mac: "
            + "quem controla o Mac pareado recebe tudo o que você digitar no Mellon."
        if let mac = model.pairedMac {
            message += "\n\nIsso substitui o pareamento com “\(mac.name)”."
        }
        return message
    }
}
