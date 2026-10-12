import CoreImage.CIFilterBuiltins
import MellonCore
import SwiftUI

struct PairingView: View {
    static let windowID = "pairing"

    @Bindable var model: MacModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            MellonEmblem(size: 48)
                .padding(.top, 8)

            switch model.phase {
            case let .pairing(invitation):
                invitationContent(invitation)
            case let .confirming(pending):
                confirmationContent(pending)
            case let .justPaired(phoneName):
                pairedContent(phoneName)
            default:
                startContent
            }
        }
        .padding(32)
        .frame(width: 400, height: 560)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
        .onAppear {
            if case .unpaired = model.phase { model.startPairing() }
        }
        .onDisappear { model.finishPairingFlow() }
    }

    private func invitationContent(_ invitation: PairingInvitation) -> some View {
        VStack(spacing: 18) {
            heading("Diga amigo e entre", "Abra o Mellon no iPhone e escaneie o código.")

            if let image = QRCode.image(for: invitation.url.absoluteString) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Theme.ithildin.opacity(0.35), radius: 24)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(invitation.expiresAt.timeIntervalSince(context.date)))
                Text("Expira em \(remaining / 60):\(String(format: "%02d", remaining % 60))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.mist)
            }

            Spacer(minLength: 0)
            Button("Cancelar") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func confirmationContent(_ pending: MacModel.PendingPhone) -> some View {
        VStack(spacing: 18) {
            heading("\(pending.name) quer se conectar", "Confira se o mesmo código aparece no iPhone.")

            Text(pending.code)
                .font(.system(size: 48, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.starlight)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.ithildin.opacity(0.4)))

            Label("Só permita se você estiver com este iPhone em mãos.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(Theme.mist)

            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button("Recusar") { model.rejectPendingPhone() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Permitir") { model.approvePendingPhone() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func pairedContent(_ phoneName: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.success)
                .padding(.top, 24)
            heading("Pareado com \(phoneName)", "Só este iPhone pode controlar o Mac. Você pode trocar de aparelho pelo menu do Mellon.")
            Spacer(minLength: 0)
            Button("Concluir") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
    }

    private var startContent: some View {
        VStack(spacing: 18) {
            heading("Parear outro iPhone", "O iPhone atual deixará de ter acesso quando o novo for permitido.")
            Spacer(minLength: 0)
            Button("Gerar código") { model.startPairing() }
                .buttonStyle(PrimaryButtonStyle())
            Button("Cancelar") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(Theme.title(24))
                .foregroundStyle(Theme.starlight)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(Theme.mist)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum QRCode {
    static func image(for string: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
