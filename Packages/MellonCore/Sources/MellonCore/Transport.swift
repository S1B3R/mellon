import CryptoKit
import Foundation
import Network

public enum MellonService {
    /// Advertised only while the Mac shows a pairing QR code.
    public static let pairingType = "_mellon-pair._tcp"
    /// Advertised while the Mac is paired and waiting for its iPhone.
    public static let sessionType = "_mellon._tcp"

    static let pairingIdentity = "mellon-pairing-v1"
    static let sessionIdentity = "mellon-session-v1"
}

public extension NWParameters {
    /// TCP + TLS 1.2 with a pre-shared key and an ephemeral ECDHE exchange. The handshake only
    /// completes when both sides hold the same key, which gives mutual authentication without
    /// certificates; ECDHE adds forward secrecy, so a key leaked later cannot decrypt past sessions.
    static func mellon(key: SymmetricKey, identity: String) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        let keyData = key.withUnsafeBytes { DispatchData(bytes: $0) }
        let identityData = Data(identity.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(options, keyData as __DispatchData, identityData as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(options, tls_ciphersuite_t(rawValue: TLSCipher.required)!)
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 10
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10

        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = false
        parameters.prohibitedInterfaceTypes = [.cellular]
        return parameters
    }

    static func mellonPairing(secret: Data) -> NWParameters {
        .mellon(key: MellonCrypto.pairingKey(secret: secret), identity: MellonService.pairingIdentity)
    }

    static func mellonSession(key: SymmetricKey) -> NWParameters {
        .mellon(key: key, identity: MellonService.sessionIdentity)
    }
}

enum TLSCipher {
    /// TLS_ECDHE_PSK_WITH_CHACHA20_POLY1305_SHA256 (RFC 7905). Channels refuse anything else.
    static let required: UInt16 = 0xCCAC
}

public struct InsecureCipherError: Error {}

/// Only peers on the local network may connect: private IPv4 ranges, link-local and loopback
/// addresses, and IPv6 unique-local addresses.
public enum LocalNetworkPolicy {
    public static func isLocal(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        switch host {
        case let .ipv4(address):
            return isLocal(address)
        case let .ipv6(address):
            if let mapped = address.asIPv4 { return isLocal(mapped) }
            let first = address.rawValue.first ?? 0
            return address.isLoopback || address.isLinkLocal || (first & 0xFE) == 0xFC
        case .name:
            return false
        @unknown default:
            return false
        }
    }

    static func isLocal(_ address: IPv4Address) -> Bool {
        let b = [UInt8](address.rawValue)
        return address.isLoopback || address.isLinkLocal
            || b[0] == 10
            || (b[0] == 172 && (16...31).contains(b[1]))
            || (b[0] == 192 && b[1] == 168)
    }
}

/// Caps how many new connections a listener accepts per time window.
public struct ConnectionThrottle: Sendable {
    public let limit: Int
    public let window: TimeInterval
    private var attempts: [Date] = []

    public init(limit: Int = 10, window: TimeInterval = 60) {
        self.limit = limit
        self.window = window
    }

    public mutating func allow(now: Date = Date()) -> Bool {
        attempts.removeAll { now.timeIntervalSince($0) >= window }
        guard attempts.count < limit else { return false }
        attempts.append(now)
        return true
    }
}

/// Listener that accepts TLS-PSK connections from the local network only.
public final class SecureListener: @unchecked Sendable {
    public enum Event: Sendable {
        case ready(port: UInt16)
        case connection(NWConnection)
        case failed(any Error)
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "app.mellon.listener")
    private var throttle = ConnectionThrottle()

    /// - Parameter service: Bonjour type and instance name to advertise, or nil to not advertise.
    public init(parameters: NWParameters, service: (type: String, name: String)?, port: NWEndpoint.Port = .any) throws {
        listener = try NWListener(using: parameters, on: port)
        if let service {
            listener.service = NWListener.Service(name: service.name, type: service.type)
        }
    }

    public func start(_ handler: @escaping @Sendable (Event) -> Void) {
        listener.stateUpdateHandler = { [listener] state in
            switch state {
            case .ready: handler(.ready(port: listener.port?.rawValue ?? 0))
            case let .failed(error): handler(.failed(error))
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, LocalNetworkPolicy.isLocal(connection.endpoint), self.throttle.allow() else {
                connection.cancel()
                return
            }
            handler(.connection(connection))
        }
        listener.start(queue: queue)
    }

    public func stop() {
        listener.cancel()
    }
}

/// Framed, typed messages over an `NWConnection`. Events are delivered on a private queue.
public final class MessageChannel<Incoming: Decodable & Sendable, Outgoing: Encodable & Sendable>: @unchecked Sendable {
    public enum Event: Sendable {
        case ready
        case message(Incoming)
        case closed((any Error)?)
    }

    public let connection: NWConnection
    private let queue = DispatchQueue(label: "app.mellon.channel")
    private let handshakeTimeout: TimeInterval
    private var decoder = FrameDecoder()
    private var handler: (@Sendable (Event) -> Void)?
    private var isReady = false
    private var isClosed = false

    public init(connection: NWConnection, handshakeTimeout: TimeInterval = 10) {
        self.connection = connection
        self.handshakeTimeout = handshakeTimeout
    }

    public convenience init(to endpoint: NWEndpoint, parameters: NWParameters) {
        self.init(connection: NWConnection(to: endpoint, using: parameters))
    }

    public func start(_ handler: @escaping @Sendable (Event) -> Void) {
        queue.async { [self] in
            self.handler = handler
            connection.stateUpdateHandler = { [weak self] state in self?.handle(state) }
            connection.start(queue: queue)
            // A peer that opens a socket but never finishes the TLS handshake gets dropped.
            queue.asyncAfter(deadline: .now() + handshakeTimeout) { [weak self] in
                guard let self, !self.isReady else { return }
                self.close(NWError.posix(.ETIMEDOUT))
            }
        }
    }

    public func send(_ message: Outgoing) {
        guard let data = try? Frame.encode(message) else { return }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error { self?.close(error) }
        })
    }

    public func cancel() {
        queue.async { [weak self] in self?.close(nil) }
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            guard connection.negotiatedTLS?.cipherSuite == TLSCipher.required else {
                close(InsecureCipherError())
                return
            }
            isReady = true
            handler?(.ready)
            receive()
        case let .waiting(error), let .failed(error):
            close(error)
        case .cancelled:
            close(nil)
        default:
            break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Frame.maxLength) { [weak self] data, _, isComplete, error in
            guard let self, !self.isClosed else { return }
            if let data, !data.isEmpty {
                do {
                    for frame in try self.decoder.append(data) {
                        self.handler?(.message(try JSONDecoder().decode(Incoming.self, from: frame)))
                    }
                } catch {
                    self.close(error)
                    return
                }
            }
            if isComplete || error != nil {
                self.close(error)
            } else {
                self.receive()
            }
        }
    }

    private func close(_ error: (any Error)?) {
        guard !isClosed else { return }
        isClosed = true
        connection.cancel()
        handler?(.closed(error))
        handler = nil
    }
}

public extension NWConnection {
    /// Negotiated TLS version and cipher suite, available once the connection is ready.
    var negotiatedTLS: (version: tls_protocol_version_t, cipherSuite: UInt16)? {
        guard let metadata = metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else { return nil }
        let securityMetadata = metadata.securityProtocolMetadata
        return (sec_protocol_metadata_get_negotiated_tls_protocol_version(securityMetadata),
                sec_protocol_metadata_get_negotiated_tls_ciphersuite(securityMetadata).rawValue)
    }
}
