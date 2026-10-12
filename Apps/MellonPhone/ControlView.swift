import MellonCore
import SwiftUI

struct ControlView: View {
    @Bindable var model: PhoneModel
    @State private var typing = false
    @State private var scanning = false
    @State private var confirmingForget = false

    private var connected: Bool { model.phase == .connected }

    var body: some View {
        VStack(spacing: 14) {
            header

            if model.macNeedsAccessibility {
                Label("No Mac, permita a Acessibilidade para o Mellon pelo menu da barra.", systemImage: "hand.raised.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            trackpad

            if typing {
                specialKeys
            } else {
                mediaControls
            }

            KeyboardCapture(
                isActive: $typing,
                onText: { text in model.send(text == "\n" ? .key(.returnKey, modifiers: []) : .text(text)) },
                onDelete: { model.send(.key(.delete, modifiers: [])) }
            )
            .frame(width: 0, height: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .sheet(isPresented: $scanning) {
            ScannerSheet { url in
                scanning = false
                model.handle(url: url)
            }
        }
        .confirmationDialog("Esquecer \(model.pairedMac?.name ?? "Mac")?", isPresented: $confirmingForget, titleVisibility: .visible) {
            Button("Esquecer", role: .destructive) { model.forgetMac() }
        } message: {
            Text("Para remover o acesso de vez, use também “Esquecer iPhone” no Mac.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            StatusDot(color: connected ? Theme.success : Theme.ithildin, pulsing: !connected)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.pairedMac?.name ?? "Mac")
                    .font(.headline)
                    .foregroundStyle(Theme.starlight)
                Text(connected ? "Conectado" : "Procurando na rede…")
                    .font(.caption)
                    .foregroundStyle(Theme.mist)
            }
            Spacer()
            Button {
                typing.toggle()
            } label: {
                Image(systemName: typing ? "keyboard.chevron.compact.down" : "keyboard")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
            }
            .disabled(!connected)
            Menu {
                Button("Parear outro Mac", systemImage: "qrcode.viewfinder") { scanning = true }
                Button("Esquecer este Mac", systemImage: "trash", role: .destructive) { confirmingForget = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
            }
        }
        .foregroundStyle(Theme.starlight)
        .padding(.top, 8)
    }

    private var trackpad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    RadialGradient(colors: [Theme.ithildin.opacity(0.10), Theme.surface],
                                   center: .center, startRadius: 10, endRadius: 400)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(connected ? Theme.ithildin.opacity(0.35) : Theme.border, lineWidth: 1)
                )

            VStack(spacing: 6) {
                if connected {
                    Image(systemName: "hand.point.up.left").font(.title2)
                    Text("Toque para clicar · dois dedos para rolar\nToque com dois dedos para o botão direito\nSegure para arrastar")
                        .multilineTextAlignment(.center)
                } else {
                    ProgressView().tint(Theme.ithildin)
                    Text("Abra o Mellon no Mac e fique na mesma rede Wi‑Fi.")
                        .multilineTextAlignment(.center)
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.mist.opacity(0.7))
            .allowsHitTesting(false)

            TrackpadSurface { event in
                switch event {
                case let .move(dx, dy): model.send(.pointerMove(dx: dx, dy: dy))
                case let .scroll(dx, dy): model.send(.scroll(dx: dx, dy: dy))
                case let .click(button): model.send(.click(button))
                case .dragBegan: model.send(.buttonDown(.left))
                case .dragEnded: model.send(.buttonUp(.left))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .disabled(!connected)
        }
    }

    private var mediaControls: some View {
        HStack(spacing: 10) {
            mediaButton("backward.fill", .previous)
            mediaButton("playpause.fill", .playPause)
            mediaButton("forward.fill", .next)
            Divider().frame(height: 28).overlay(Theme.border)
            mediaButton("speaker.slash.fill", .mute)
            mediaButton("speaker.wave.1.fill", .volumeDown)
            mediaButton("speaker.wave.3.fill", .volumeUp)
        }
        .disabled(!connected)
    }

    private var specialKeys: some View {
        HStack(spacing: 8) {
            keyButton("esc", .escape)
            keyButton("tab", .tab)
            Spacer(minLength: 0)
            keyButton(systemImage: "arrow.left", .left)
            keyButton(systemImage: "arrow.down", .down)
            keyButton(systemImage: "arrow.up", .up)
            keyButton(systemImage: "arrow.right", .right)
        }
    }

    private func mediaButton(_ symbol: String, _ key: MediaKey) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            model.send(.media(key))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .foregroundStyle(Theme.starlight)
    }

    private func keyButton(_ title: String? = nil, systemImage: String? = nil, _ key: Key) -> some View {
        Button {
            model.send(.key(key, modifiers: []))
        } label: {
            Group {
                if let systemImage { Image(systemName: systemImage) } else { Text(title ?? "") }
            }
            .font(.system(.callout, design: .rounded, weight: .medium))
            .frame(minWidth: 44, minHeight: 40)
            .padding(.horizontal, 4)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .foregroundStyle(Theme.starlight)
    }
}
