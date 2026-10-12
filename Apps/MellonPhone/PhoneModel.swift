import CryptoKit
import MellonCore
import Network
import Observation
import UIKit

@MainActor
@Observable
final class PhoneModel {
    enum Phase: Equatable {
        case unpaired
        case pairing(macName: String, code: String)
        case connecting
        case connected
    }

    typealias PairingChannel = MessageChannel<PairingResponse, PairingRequest>
    typealias SessionChannel = MessageChannel<MacMessage, ControlMessage>

    private(set) var phase: Phase = .unpaired
    private(set) var pairedMac: PairedMac?
    private(set) var macNeedsAccessibility = false
    var errorMessage: String?

    private let store = KeychainStore(service: "app.mellon.phone")
    private let identity: DeviceIdentity
    private let phoneName = UIDevice.current.name

    private var pairingChannel: PairingChannel?
    private var sessionChannel: SessionChannel?
    private var reconnectTask: Task<Void, Never>?
    private var retryDelay: Duration = .seconds(1)
    private var isActive = true

    private static let pairedMacAccount = "pairedMac"

    init() {
        do {
            identity = try DeviceIdentity.loadOrCreate(in: store)
        } catch {
            fatalError("Mellon could not access the Keychain: \(error)")
        }
        pairedMac = try? store.readCodable(PairedMac.self, Self.pairedMacAccount)
        if pairedMac != nil { connect() }
    }

    // MARK: Lifecycle

    func setActive(_ active: Bool) {
        isActive = active
        if active {
            connect()
        } else {
            // Nothing stays connected in the background.
            reconnectTask?.cancel()
            sessionChannel?.cancel()
            sessionChannel = nil
            if pairedMac != nil, phase == .connected { phase = .connecting }
        }
    }

    // MARK: Pairing

    func handle(url: URL) {
        do {
            pair(with: try PairingInvitation(url: url))
        } catch {
            errorMessage = "Este não é um código do Mellon."
        }
    }

    func pair(with invitation: PairingInvitation) {
        guard !invitation.isExpired() else {
            errorMessage = "Este código expirou. Gere um novo no Mac."
            return
        }
        pairingChannel?.cancel()
        let code = MellonCrypto.pairingCode(macPublicKey: invitation.macPublicKey, phonePublicKey: identity.publicKey)
        phase = .pairing(macName: invitation.macName, code: code)

        let channel = PairingChannel(
            to: .service(name: invitation.serviceName, type: MellonService.pairingType, domain: "local.", interface: nil),
            parameters: .mellonPairing(secret: invitation.secret)
        )
        pairingChannel = channel
        channel.start { [weak self] event in
            Task { @MainActor in self?.handlePairing(event, invitation: invitation, channel: channel) }
        }
    }

    func cancelPairing() {
        pairingChannel?.cancel()
        pairingChannel = nil
        phase = pairedMac == nil ? .unpaired : .connecting
    }

    private func handlePairing(_ event: PairingChannel.Event, invitation: PairingInvitation, channel: PairingChannel) {
        guard pairingChannel === channel else { return }
        switch event {
        case .ready:
            channel.send(.pair(phoneName: phoneName, phonePublicKey: identity.publicKey,
                               protocolVersion: MellonProtocol.version))
        case let .message(.accepted(serviceName)):
            let mac = PairedMac(name: invitation.macName, publicKey: invitation.macPublicKey, serviceName: serviceName)
            do {
                try store.writeCodable(mac, for: Self.pairedMacAccount)
            } catch {
                errorMessage = "Não foi possível salvar o pareamento."
                return
            }
            pairingChannel = nil
            channel.cancel()
            disconnectSession()
            pairedMac = mac
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            connect()
        case .message(.rejected):
            pairingChannel = nil
            channel.cancel()
            errorMessage = "O Mac recusou o pareamento."
            phase = pairedMac == nil ? .unpaired : .connecting
        case .closed:
            pairingChannel = nil
            errorMessage = "Não foi possível falar com o Mac. Confira se os dois estão na mesma rede Wi‑Fi e se o código ainda está na tela."
            phase = pairedMac == nil ? .unpaired : .connecting
        }
    }

    func forgetMac() {
        disconnectSession()
        try? store.delete(Self.pairedMacAccount)
        pairedMac = nil
        macNeedsAccessibility = false
        phase = .unpaired
    }

    // MARK: Session

    private func connect() {
        guard isActive, let mac = pairedMac, sessionChannel == nil, pairingChannel == nil else { return }
        reconnectTask?.cancel()
        let key: SymmetricKey
        do {
            key = try MellonCrypto.sessionKey(identity: identity, peerPublicKey: mac.publicKey,
                                              macPublicKey: mac.publicKey, phonePublicKey: identity.publicKey)
        } catch {
            errorMessage = "O pareamento salvo é inválido. Pareie novamente."
            forgetMac()
            return
        }
        phase = .connecting
        let channel = SessionChannel(
            to: .service(name: mac.serviceName, type: MellonService.sessionType, domain: "local.", interface: nil),
            parameters: .mellonSession(key: key)
        )
        sessionChannel = channel
        channel.start { [weak self] event in
            Task { @MainActor in self?.handleSession(event, channel: channel) }
        }
    }

    private func disconnectSession() {
        reconnectTask?.cancel()
        sessionChannel?.cancel()
        sessionChannel = nil
    }

    private func handleSession(_ event: SessionChannel.Event, channel: SessionChannel) {
        guard sessionChannel === channel else { return }
        switch event {
        case .ready:
            retryDelay = .seconds(1)
            macNeedsAccessibility = false
            channel.send(.hello(phoneName: phoneName, protocolVersion: MellonProtocol.version))
            phase = .connected
        case .message(.welcome):
            break
        case .message(.accessibilityRequired):
            macNeedsAccessibility = true
        case .closed:
            sessionChannel = nil
            guard pairedMac != nil else { return }
            phase = .connecting
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, .seconds(8))
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.connect()
        }
    }

    func send(_ message: ControlMessage) {
        guard phase == .connected else { return }
        sessionChannel?.send(message)
    }
}

