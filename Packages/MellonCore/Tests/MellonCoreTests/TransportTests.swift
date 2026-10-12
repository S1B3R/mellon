import CryptoKit
import Foundation
import Network
import Testing
@testable import MellonCore

struct FramingTests {
    @Test func reassemblesChunkedStream() throws {
        let messages: [ControlMessage] = [
            .hello(phoneName: "iPhone", protocolVersion: 1),
            .pointerMove(dx: 1.5, dy: -2),
            .key(.returnKey, modifiers: [.command]),
            .text("Mellon ✨"),
        ]
        let stream = try messages.map(Frame.encode).reduce(Data(), +)
        var decoder = FrameDecoder()
        var decoded: [ControlMessage] = []
        for byte in stream {
            for frame in try decoder.append(Data([byte])) {
                decoded.append(try JSONDecoder().decode(ControlMessage.self, from: frame))
            }
        }
        #expect(decoded == messages)
    }

    @Test func rejectsOversizedFrames() {
        var decoder = FrameDecoder()
        var header = UInt32(Frame.maxLength + 1).bigEndian
        #expect(throws: Frame.Error.self) {
            _ = try decoder.append(Data(bytes: &header, count: 4))
        }
    }
}

struct PolicyTests {
    @Test(arguments: ["192.168.1.20", "10.0.0.5", "172.16.4.1", "172.31.255.1", "169.254.10.10", "127.0.0.1",
                      "fe80::1", "fd12:3456::1", "::1", "::ffff:192.168.0.2"])
    func acceptsLocalAddresses(_ host: String) {
        #expect(LocalNetworkPolicy.isLocal(.hostPort(host: NWEndpoint.Host(host), port: 1)))
    }

    @Test(arguments: ["8.8.8.8", "172.32.0.1", "100.64.0.1", "2001:4860::8888", "::ffff:8.8.8.8"])
    func rejectsPublicAddresses(_ host: String) {
        #expect(!LocalNetworkPolicy.isLocal(.hostPort(host: NWEndpoint.Host(host), port: 1)))
    }

    @Test func throttleCapsAttemptsPerWindow() {
        var throttle = ConnectionThrottle(limit: 3, window: 60)
        let now = Date()
        #expect((0..<3).allSatisfy { _ in throttle.allow(now: now) })
        let blocked = throttle.allow(now: now)
        let later = throttle.allow(now: now.addingTimeInterval(61))
        #expect(!blocked)
        #expect(later)
    }
}

/// End-to-end over loopback: a real TLS-PSK handshake between a listener and a client.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct SecureChannelTests {
    typealias MacChannel = MessageChannel<ControlMessage, MacMessage>
    typealias PhoneChannel = MessageChannel<MacMessage, ControlMessage>

    final class Box<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }

    /// Connects a client with `clientKey` to a listener with `serverKey`, sends a message, and
    /// returns what the server received (nil if the connection never got through).
    func exchange(serverKey: SymmetricKey, clientKey: SymmetricKey) async throws -> (message: ControlMessage?, cipher: UInt16?) {
        let listener = try SecureListener(parameters: .mellonSession(key: serverKey), service: nil)
        let serverChannel = Box<MacChannel?>(nil)
        let negotiated = Box<UInt16?>(nil)
        defer {
            listener.stop()
            serverChannel.value?.cancel()
        }

        let message: ControlMessage? = try await withCheckedThrowingContinuation { continuation in
            let resumed = Box(false)
            let lock = NSLock()
            let finish: @Sendable (Result<ControlMessage?, any Error>) -> Void = { result in
                lock.withLock {
                    guard !resumed.value else { return }
                    resumed.value = true
                    continuation.resume(with: result)
                }
            }

            listener.start { event in
                switch event {
                case let .ready(port):
                    let client = PhoneChannel(
                        to: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!),
                        parameters: .mellonSession(key: clientKey)
                    )
                    client.start { event in
                        switch event {
                        case .ready:
                            negotiated.value = client.connection.negotiatedTLS?.cipherSuite
                            client.send(.hello(phoneName: "Sam", protocolVersion: 1))
                        case .closed: finish(.success(nil))
                        case .message: break
                        }
                    }
                case let .connection(connection):
                    let channel = MacChannel(connection: connection)
                    serverChannel.value = channel
                    channel.start { event in
                        if case let .message(message) = event { finish(.success(message)) }
                    }
                case let .failed(error):
                    finish(.failure(error))
                }
            }
        }
        return (message, negotiated.value)
    }

    @Test func matchingKeysExchangeMessages() async throws {
        let key = SymmetricKey(size: .bits256)
        let received = try await exchange(serverKey: key, clientKey: key)
        #expect(received.message == .hello(phoneName: "Sam", protocolVersion: 1))
        #expect(received.cipher == TLSCipher.required)
    }

    @Test func wrongKeyIsRejected() async throws {
        let received = try await exchange(serverKey: SymmetricKey(size: .bits256), clientKey: SymmetricKey(size: .bits256))
        #expect(received.message == nil)
    }
}
