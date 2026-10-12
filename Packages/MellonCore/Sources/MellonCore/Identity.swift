import CryptoKit
import Foundation

/// Long-term identity of a device: a Curve25519 key pair that never leaves the device.
public struct DeviceIdentity: Sendable {
    public let privateKey: Curve25519.KeyAgreement.PrivateKey

    public init() {
        privateKey = Curve25519.KeyAgreement.PrivateKey()
    }

    public init(rawRepresentation: Data) throws {
        privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: rawRepresentation)
    }

    public var rawRepresentation: Data { privateKey.rawRepresentation }
    public var publicKey: Data { privateKey.publicKey.rawRepresentation }

    /// Loads the identity stored under `account`, creating and persisting a new one on first use.
    public static func loadOrCreate(in store: SecureStore, account: String = "identity") throws -> DeviceIdentity {
        if let data = try store.read(account) {
            return try DeviceIdentity(rawRepresentation: data)
        }
        let identity = DeviceIdentity()
        try store.write(identity.rawRepresentation, for: account)
        return identity
    }
}

public enum MellonCrypto {
    static let pairingSalt = Data("mellon/pairing/v1".utf8)
    static let sessionSalt = Data("mellon/session/v1".utf8)
    static let codeSalt = Data("mellon/code/v1".utf8)

    /// Key protecting the short-lived pairing channel, derived from the one-time secret in the QR code.
    public static func pairingKey(secret: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secret),
            salt: pairingSalt,
            outputByteCount: 32
        )
    }

    /// Key protecting every session after pairing. Only the two paired devices can compute it:
    /// it requires one side's private key and the other side's public key.
    public static func sessionKey(
        identity: DeviceIdentity,
        peerPublicKey: Data,
        macPublicKey: Data,
        phonePublicKey: Data
    ) throws -> SymmetricKey {
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)
        let shared = try identity.privateKey.sharedSecretFromKeyAgreement(with: peer)
        return shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: sessionSalt,
            sharedInfo: macPublicKey + phonePublicKey,
            outputByteCount: 32
        )
    }

    /// Six-digit code both screens show during pairing, so the user can confirm they are pairing
    /// the devices they think they are.
    public static func pairingCode(macPublicKey: Data, phonePublicKey: Data) -> String {
        let digest = SHA256.hash(data: codeSalt + macPublicKey + phonePublicKey)
        let value = digest.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) } % 1_000_000
        let digits = String(format: "%06u", value)
        return "\(digits.prefix(3)) \(digits.suffix(3))"
    }

    public static func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return data
    }

    /// Random, non-identifying Bonjour instance name (e.g. "Mellon-3F9A1C2B").
    public static func randomServiceName() -> String {
        "Mellon-" + randomBytes(4).map { String(format: "%02X", $0) }.joined()
    }
}
