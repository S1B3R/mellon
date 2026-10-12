import CryptoKit
import Foundation
import Testing
@testable import MellonCore

struct CryptoTests {
    @Test func sessionKeyMatchesOnBothSides() throws {
        let mac = DeviceIdentity()
        let phone = DeviceIdentity()
        let macSide = try MellonCrypto.sessionKey(identity: mac, peerPublicKey: phone.publicKey,
                                                  macPublicKey: mac.publicKey, phonePublicKey: phone.publicKey)
        let phoneSide = try MellonCrypto.sessionKey(identity: phone, peerPublicKey: mac.publicKey,
                                                    macPublicKey: mac.publicKey, phonePublicKey: phone.publicKey)
        #expect(macSide == phoneSide)
    }

    @Test func impostorCannotDeriveSessionKey() throws {
        let mac = DeviceIdentity()
        let phone = DeviceIdentity()
        let impostor = DeviceIdentity()
        let real = try MellonCrypto.sessionKey(identity: mac, peerPublicKey: phone.publicKey,
                                               macPublicKey: mac.publicKey, phonePublicKey: phone.publicKey)
        // The impostor knows both public keys but only its own private key.
        let forged = try MellonCrypto.sessionKey(identity: impostor, peerPublicKey: mac.publicKey,
                                                 macPublicKey: mac.publicKey, phonePublicKey: phone.publicKey)
        #expect(real != forged)
    }

    @Test func pairingCodeIsStableAndFormatted() {
        let mac = DeviceIdentity().publicKey
        let phone = DeviceIdentity().publicKey
        let code = MellonCrypto.pairingCode(macPublicKey: mac, phonePublicKey: phone)
        #expect(code == MellonCrypto.pairingCode(macPublicKey: mac, phonePublicKey: phone))
        #expect(code.count == 7)
        #expect(code.filter(\.isNumber).count == 6)
        #expect(code != MellonCrypto.pairingCode(macPublicKey: mac, phonePublicKey: DeviceIdentity().publicKey))
    }

    @Test func identityIsPersisted() throws {
        let store = MemoryStore()
        let first = try DeviceIdentity.loadOrCreate(in: store)
        let second = try DeviceIdentity.loadOrCreate(in: store)
        #expect(first.publicKey == second.publicKey)
    }
}

struct PairingInvitationTests {
    @Test func roundTripsThroughURL() throws {
        let invitation = PairingInvitation.make(macName: "MacBook do Frodo", macIdentity: DeviceIdentity())
        let parsed = try PairingInvitation(url: invitation.url)
        #expect(parsed.macName == invitation.macName)
        #expect(parsed.macPublicKey == invitation.macPublicKey)
        #expect(parsed.secret == invitation.secret)
        #expect(parsed.serviceName == invitation.serviceName)
        #expect(Int(parsed.expiresAt.timeIntervalSince1970) == Int(invitation.expiresAt.timeIntervalSince1970))
    }

    @Test func expires() {
        let invitation = PairingInvitation.make(macName: "Mac", macIdentity: DeviceIdentity(), lifetime: 120)
        #expect(!invitation.isExpired())
        #expect(invitation.isExpired(now: Date().addingTimeInterval(121)))
    }

    @Test func rejectsForeignAndMalformedURLs() throws {
        #expect(throws: PairingInvitation.ParseError.notAnInvitation) {
            try PairingInvitation(url: URL(string: "https://example.com/pair")!)
        }
        #expect(throws: PairingInvitation.ParseError.unsupportedVersion) {
            try PairingInvitation(url: URL(string: "mellon://pair?v=99")!)
        }
        #expect(throws: PairingInvitation.ParseError.malformed) {
            try PairingInvitation(url: URL(string: "mellon://pair?v=1&m=Mac&k=AAAA&s=AAAA&n=x&e=1")!)
        }
    }
}
