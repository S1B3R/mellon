import AppKit
import ApplicationServices
import MellonCore
import Network
import Observation

@MainActor
@Observable
final class MacModel {
    enum Phase: Equatable {
        case unpaired
        /// Showing a QR code and waiting for the iPhone to scan it.
        case pairing(PairingInvitation)
        /// An iPhone answered the invitation; the user must confirm the code.
        case confirming(PendingPhone)
        case justPaired(phoneName: String)
        case waiting
        case connected
        case paused
    }

    struct PendingPhone: Equatable {
        let name: String
        let publicKey: Data
        let code: String
    }

    typealias PairingChannel = MessageChannel<PairingRequest, PairingResponse>
    typealias SessionChannel = MessageChannel<ControlMessage, MacMessage>

    private(set) var phase: Phase = .unpaired
    private(set) var pairedPhone: PairedPhone?
    private(set) var hasAccessibility = AXIsProcessTrusted()
    var errorMessage: String?

    let macName = Host.current().localizedName ?? "Mac"

    private let store = KeychainStore(service: "app.mellon.mac")
    private let identity: DeviceIdentity
    private let input = InputController()

    private var invitation: PairingInvitation?
    private var pairingListener: SecureListener?
    private var pairingChannel: PairingChannel?
    private var expiryTask: Task<Void, Never>?

    private var sessionListener: SecureListener?
    private var sessionChannel: SessionChannel?

    private static let pairedPhoneAccount = "pairedPhone"

    init() {
        do {
            identity = try DeviceIdentity.loadOrCreate(in: store)
        } catch {
            fatalError("Mellon could not access the Keychain: \(error)")
        }
        pairedPhone = try? store.readCodable(PairedPhone.self, Self.pairedPhoneAccount)
        if pairedPhone != nil {
            phase = .waiting
            startSessionListener()
        }
        watchAccessibility()
    }

    var isConnected: Bool { phase == .connected }

    // MARK: Accessibility

    func requestAccessibility() {
        // Literal value of kAXTrustedCheckOptionPrompt, which Swift 6 flags as a mutable global.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        hasAccessibility = AXIsProcessTrustedWithOptions(options)
        if !hasAccessibility,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func watchAccessibility() {
        Task { [weak self] in
            while let self, !self.hasAccessibility {
                try? await Task.sleep(for: .seconds(1))
                self.hasAccessibility = AXIsProcessTrusted()
            }
        }
    }

    // MARK: Pairing

    func startPairing() {
        cancelPairing()
        let invitation = PairingInvitation.make(macName: macName, macIdentity: identity)
        do {
            let listener = try SecureListener(
                parameters: .mellonPairing(secret: invitation.secret),
                service: (MellonService.pairingType, invitation.serviceName)
            )
            listener.start { [weak self] event in
                Task { @MainActor in self?.handlePairingListener(event) }
            }
            self.invitation = invitation
            pairingListener = listener
            phase = .pairing(invitation)
            expiryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(invitation.expiresAt.timeIntervalSinceNow))
                guard let self, !Task.isCancelled, self.invitation == invitation else { return }
                self.cancelPairing()
            }
        } catch {
            errorMessage = "Não foi possível iniciar o pareamento: \(error.localizedDescription)"
        }
    }

    func cancelPairing() {
        expiryTask?.cancel()
        expiryTask = nil
        pairingListener?.stop()
        pairingListener = nil
        pairingChannel?.cancel()
        pairingChannel = nil
        invitation = nil
        switch phase {
        case .pairing, .confirming, .justPaired:
            phase = pairedPhone == nil ? .unpaired : (sessionChannel == nil ? .waiting : .connected)
        default:
            break
        }
    }

    func approvePendingPhone() {
        guard case let .confirming(pending) = phase, let channel = pairingChannel else { return }
        let phone = PairedPhone(name: pending.name, publicKey: pending.publicKey,
                                serviceName: MellonCrypto.randomServiceName())
        do {
            try store.writeCodable(phone, for: Self.pairedPhoneAccount)
        } catch {
            errorMessage = "Não foi possível salvar o pareamento: \(error.localizedDescription)"
            return
        }
        // Replacing a previous phone: its session ends and its key stops working.
        stopSession()
        pairedPhone = phone
        channel.send(.accepted(sessionServiceName: phone.serviceName))

        // Stop advertising right away; give the phone a moment to read the answer and hang up.
        pairingListener?.stop()
        pairingListener = nil
        expiryTask?.cancel()
        invitation = nil
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            channel.cancel()
            if self?.pairingChannel === channel { self?.pairingChannel = nil }
        }

        phase = .justPaired(phoneName: phone.name)
        startSessionListener()
    }

    func rejectPendingPhone() {
        pairingChannel?.send(.rejected)
        // Someone unexpected answered: end this invitation entirely instead of reopening it.
        cancelPairing()
    }

    private func handlePairingListener(_ event: SecureListener.Event) {
        switch event {
        case let .connection(connection):
            // One pairing attempt at a time.
            guard pairingChannel == nil else {
                connection.cancel()
                return
            }
            let channel = PairingChannel(connection: connection)
            pairingChannel = channel
            channel.start { [weak self] event in
                Task { @MainActor in self?.handlePairingChannel(event, channel: channel) }
            }
        case let .failed(error):
            errorMessage = "O pareamento falhou: \(error.localizedDescription)"
            cancelPairing()
        case .ready:
            break
        }
    }

    private func handlePairingChannel(_ event: PairingChannel.Event, channel: PairingChannel) {
        guard pairingChannel === channel else { return }
        switch event {
        case .ready:
            break
        case let .message(.pair(phoneName, phonePublicKey, version)):
            guard case .pairing = phase,
                  version == MellonProtocol.version,
                  phonePublicKey.count == 32
            else {
                channel.send(.rejected)
                channel.cancel()
                return
            }
            let code = MellonCrypto.pairingCode(macPublicKey: identity.publicKey, phonePublicKey: phonePublicKey)
            let name = String(phoneName.prefix(64))
            phase = .confirming(PendingPhone(name: name.isEmpty ? "iPhone" : name, publicKey: phonePublicKey, code: code))
            NSApp.activate(ignoringOtherApps: true)
        case .closed:
            pairingChannel = nil
            if case .confirming = phase, let invitation {
                phase = .pairing(invitation)
            }
        }
    }

    func finishPairingFlow() {
        if case .justPaired = phase {
            phase = sessionChannel == nil ? .waiting : .connected
        } else {
            cancelPairing()
        }
    }

    // MARK: Session

    private func startSessionListener() {
        guard let phone = pairedPhone, sessionListener == nil else { return }
        do {
            let key = try MellonCrypto.sessionKey(identity: identity, peerPublicKey: phone.publicKey,
                                                  macPublicKey: identity.publicKey, phonePublicKey: phone.publicKey)
            let listener = try SecureListener(parameters: .mellonSession(key: key),
                                              service: (MellonService.sessionType, phone.serviceName))
            listener.start { [weak self] event in
                Task { @MainActor in self?.handleSessionListener(event) }
            }
            sessionListener = listener
        } catch {
            errorMessage = "Não foi possível aguardar o iPhone: \(error.localizedDescription)"
        }
    }

    private func stopSession() {
        sessionListener?.stop()
        sessionListener = nil
        sessionChannel?.cancel()
        sessionChannel = nil
        input.reset()
    }

    private func handleSessionListener(_ event: SecureListener.Event) {
        switch event {
        case let .connection(connection):
            // The TLS handshake decides whether this is our iPhone; nothing is read before that.
            let channel = SessionChannel(connection: connection)
            channel.start { [weak self] event in
                Task { @MainActor in self?.handleSessionChannel(event, channel: channel) }
            }
        case let .failed(error):
            errorMessage = "Conexão interrompida: \(error.localizedDescription)"
            sessionListener = nil
        case .ready:
            break
        }
    }

    private func handleSessionChannel(_ event: SessionChannel.Event, channel: SessionChannel) {
        switch event {
        case .ready:
            guard sessionListener != nil else {
                channel.cancel()
                return
            }
            // A reconnect from the same phone replaces the stale connection.
            if let old = sessionChannel, old !== channel { old.cancel() }
            input.reset()
            sessionChannel = channel
            channel.send(.welcome(macName: macName, protocolVersion: MellonProtocol.version))
            if !hasAccessibility { channel.send(.accessibilityRequired) }
            if case .justPaired = phase {} else { phase = .connected }
        case let .message(message):
            guard sessionChannel === channel, hasAccessibility else { return }
            input.handle(message)
        case .closed:
            guard sessionChannel === channel else { return }
            sessionChannel = nil
            input.reset()
            if phase == .connected { phase = .waiting }
        }
    }

    /// Stops accepting the iPhone until resumed.
    func pause() {
        stopSession()
        phase = .paused
    }

    func resume() {
        phase = .waiting
        startSessionListener()
    }

    func forgetPhone() {
        cancelPairing()
        stopSession()
        try? store.delete(Self.pairedPhoneAccount)
        pairedPhone = nil
        phase = .unpaired
    }
}
