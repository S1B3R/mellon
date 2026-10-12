import Foundation

/// Everything the iPhone needs to pair with the Mac. Shown on the Mac as a QR code and never
/// sent over the network: the QR code is the out-of-band channel that rules out a man in the middle.
public struct PairingInvitation: Equatable, Sendable {
    public static let scheme = "mellon"
    public static let version = 1
    public static let secretLength = 32

    public let macName: String
    public let macPublicKey: Data
    /// One-time secret; the pairing channel's TLS key is derived from it.
    public let secret: Data
    /// Bonjour instance name of the pairing listener.
    public let serviceName: String
    public let expiresAt: Date

    public init(macName: String, macPublicKey: Data, secret: Data, serviceName: String, expiresAt: Date) {
        self.macName = macName
        self.macPublicKey = macPublicKey
        self.secret = secret
        self.serviceName = serviceName
        self.expiresAt = expiresAt
    }

    public static func make(macName: String, macIdentity: DeviceIdentity, lifetime: TimeInterval = 120) -> PairingInvitation {
        PairingInvitation(
            macName: macName,
            macPublicKey: macIdentity.publicKey,
            secret: MellonCrypto.randomBytes(secretLength),
            serviceName: MellonCrypto.randomServiceName(),
            expiresAt: Date().addingTimeInterval(lifetime)
        )
    }

    public func isExpired(now: Date = Date()) -> Bool { now >= expiresAt }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "v", value: String(Self.version)),
            URLQueryItem(name: "m", value: macName),
            URLQueryItem(name: "k", value: macPublicKey.base64URLEncoded()),
            URLQueryItem(name: "s", value: secret.base64URLEncoded()),
            URLQueryItem(name: "n", value: serviceName),
            URLQueryItem(name: "e", value: String(Int(expiresAt.timeIntervalSince1970))),
        ]
        return components.url!
    }

    public enum ParseError: Error, Equatable {
        case notAnInvitation
        case unsupportedVersion
        case malformed
    }

    public init(url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == Self.scheme, components.host == "pair"
        else { throw ParseError.notAnInvitation }

        let items = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        guard items["v"] == String(Self.version) else { throw ParseError.unsupportedVersion }
        guard let macName = items["m"], !macName.isEmpty,
              let key = items["k"].flatMap(Data.init(base64URLEncoded:)), key.count == 32,
              let secret = items["s"].flatMap(Data.init(base64URLEncoded:)), secret.count == Self.secretLength,
              let serviceName = items["n"], !serviceName.isEmpty,
              let expiry = items["e"].flatMap(TimeInterval.init)
        else { throw ParseError.malformed }

        self.init(macName: macName, macPublicKey: key, secret: secret, serviceName: serviceName,
                  expiresAt: Date(timeIntervalSince1970: expiry))
    }
}

/// The iPhone as remembered by the Mac. The Mac stores at most one.
public struct PairedPhone: Codable, Equatable, Sendable {
    public let name: String
    public let publicKey: Data
    /// Bonjour instance name the Mac advertises for sessions with this phone.
    public let serviceName: String
    public let pairedAt: Date

    public init(name: String, publicKey: Data, serviceName: String, pairedAt: Date = Date()) {
        self.name = name
        self.publicKey = publicKey
        self.serviceName = serviceName
        self.pairedAt = pairedAt
    }
}

/// The Mac as remembered by the iPhone.
public struct PairedMac: Codable, Equatable, Sendable {
    public let name: String
    public let publicKey: Data
    public let serviceName: String
    public let pairedAt: Date

    public init(name: String, publicKey: Data, serviceName: String, pairedAt: Date = Date()) {
        self.name = name
        self.publicKey = publicKey
        self.serviceName = serviceName
        self.pairedAt = pairedAt
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
