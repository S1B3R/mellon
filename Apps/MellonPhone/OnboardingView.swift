import MellonCore
import SwiftUI
import VisionKit

struct OnboardingView: View {
    let model: PhoneModel
    @State private var scanning = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            MellonEmblem(size: 96)
            VStack(spacing: 8) {
                Text("Mellon").font(Theme.title(44)).foregroundStyle(Theme.starlight)
                Text("Speak friend, and control.").font(.callout).italic().foregroundStyle(Theme.mist)
            }
            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                step(1, "Abra o Mellon no Mac", "Ele fica na barra de menus.")
                step(2, "Clique em “Parear iPhone”", "Um código aparece na tela.")
                step(3, "Escaneie o código", "Só este iPhone poderá controlar o Mac.")
            }
            .padding(20)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.border))

            Button {
                scanning = true
            } label: {
                Label("Escanear código", systemImage: "qrcode.viewfinder")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
        .sheet(isPresented: $scanning) {
            ScannerSheet { url in
                scanning = false
                model.handle(url: url)
            }
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.night)
                .frame(width: 26, height: 26)
                .background(Theme.ithildin, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.starlight)
                Text(detail).font(.caption).foregroundStyle(Theme.mist)
            }
        }
    }
}

struct ScannerSheet: View {
    let onScan: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            if DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
                QRScanner(onScan: onScan).ignoresSafeArea()
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Theme.ithildin, lineWidth: 3)
                    .frame(width: 260, height: 260)
                    .frame(maxHeight: .infinity)
                    .shadow(color: Theme.ithildin.opacity(0.6), radius: 16)
            } else {
                ContentUnavailableView("Câmera indisponível",
                                       systemImage: "camera.fill",
                                       description: Text("Permita o acesso à câmera em Ajustes ou aponte a câmera do iPhone para o código no Mac."))
                    .frame(maxHeight: .infinity)
            }
            HStack {
                Text("Aponte para o código no Mac").font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2).symbolRenderingMode(.hierarchical)
                }
            }
            .padding(20)
            .background(.ultraThinMaterial)
        }
        .background(Theme.night)
    }
}

/// Camera QR scanner; reports the first Mellon pairing link it sees.
struct QRScanner: UIViewControllerRepresentable {
    let onScan: (URL) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: false
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (URL) -> Void
        private var done = false

        init(onScan: @escaping (URL) -> Void) { self.onScan = onScan }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case let .barcode(code) in items {
                guard !done, let payload = code.payloadStringValue, let url = URL(string: payload),
                      url.scheme == PairingInvitation.scheme
                else { continue }
                done = true
                scanner.stopScanning()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onScan(url)
            }
        }
    }
}

struct PairingProgressView: View {
    let macName: String
    let code: String
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            MellonEmblem(size: 72)
            VStack(spacing: 8) {
                Text("Confirme no Mac").font(Theme.title(30)).foregroundStyle(Theme.starlight)
                Text("Clique em “Permitir” em \(macName) se o código for o mesmo:")
                    .font(.callout)
                    .foregroundStyle(Theme.mist)
                    .multilineTextAlignment(.center)
            }
            Text(code)
                .font(.system(size: 44, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.starlight)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.ithildin.opacity(0.4)))
            ProgressView().tint(Theme.ithildin)
            Spacer()
            Button("Cancelar", action: onCancel).buttonStyle(SecondaryButtonStyle())
        }
        .padding(24)
    }
}
