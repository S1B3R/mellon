import SwiftUI

struct MenuView: View {
    @Bindable var model: MacModel
    @Environment(\.openWindow) private var openWindow
    @State private var confirmingForget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !model.hasAccessibility {
                accessibilityCard
            }

            statusCard

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .onTapGesture { model.errorMessage = nil }
            }

            actions
        }
        .padding(16)
        .frame(width: 320)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
        .confirmationDialog("Esquecer \(model.pairedPhone?.name ?? "iPhone")?", isPresented: $confirmingForget) {
            Button("Esquecer", role: .destructive) { model.forgetPhone() }
        } message: {
            Text("Este iPhone deixa de controlar o Mac. Para usá-lo de novo, será preciso parear outra vez.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            MellonEmblem(size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mellon").font(Theme.title(20)).foregroundStyle(Theme.starlight)
                Text("Speak friend, and control.").font(.caption).italic().foregroundStyle(Theme.mist)
            }
            Spacer()
        }
    }

    private var accessibilityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Permissão necessária", systemImage: "hand.raised.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.warning)
            Text("Para mover o cursor e digitar, o Mellon precisa da permissão de Acessibilidade.")
                .font(.caption)
                .foregroundStyle(Theme.mist)
                .fixedSize(horizontal: false, vertical: true)
            Button("Abrir Ajustes do Sistema") { model.requestAccessibility() }
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(12)
        .background(Theme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.warning.opacity(0.3)))
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            StatusDot(color: status.color, pulsing: status.pulsing)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.starlight)
                Text(status.detail).font(.caption).foregroundStyle(Theme.mist)
            }
            Spacer()
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border))
    }

    private var status: (title: String, detail: String, color: Color, pulsing: Bool) {
        let phone = model.pairedPhone?.name ?? "iPhone"
        return switch model.phase {
        case .unpaired: ("Nenhum iPhone pareado", "Pareie seu iPhone para começar.", Theme.mist, false)
        case .pairing, .confirming: ("Pareando…", "Escaneie o código com o iPhone.", Theme.ithildin, true)
        case .justPaired, .waiting: ("Aguardando \(phone)", "Abra o Mellon no iPhone.", Theme.ithildin, true)
        case .connected: ("\(phone) conectado", "Controlando este Mac.", Theme.success, false)
        case .paused: ("Controle pausado", "\(phone) não pode se conectar.", Theme.warning, false)
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 8) {
            switch model.phase {
            case .unpaired, .pairing, .confirming:
                Button("Parear iPhone") { showPairing() }
                    .buttonStyle(PrimaryButtonStyle())
            case .connected, .waiting, .justPaired:
                Button("Pausar controle") { model.pause() }
                    .buttonStyle(SecondaryButtonStyle())
            case .paused:
                Button("Retomar") { model.resume() }
                    .buttonStyle(PrimaryButtonStyle())
            }

            HStack(spacing: 8) {
                if model.pairedPhone != nil {
                    Button("Trocar de iPhone") { showPairing() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.mist)
                    Button("Esquecer iPhone") { confirmingForget = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.mist)
                }
                Spacer()
                Button("Sair") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.mist)
            }
            .font(.caption)
            .padding(.top, 4)
        }
    }

    private func showPairing() {
        if case .unpaired = model.phase { model.startPairing() }
        openWindow(id: PairingView.windowID)
        NSApp.activate(ignoringOtherApps: true)
    }
}
