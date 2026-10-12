import Foundation

public enum MellonProtocol {
    public static let version = 1
}

// MARK: - Pairing channel

/// iPhone → Mac, inside the pairing channel.
public enum PairingRequest: Codable, Equatable, Sendable {
    case pair(phoneName: String, phonePublicKey: Data, protocolVersion: Int)
}

/// Mac → iPhone, inside the pairing channel.
public enum PairingResponse: Codable, Equatable, Sendable {
    case accepted(sessionServiceName: String)
    case rejected
}

// MARK: - Session channel

/// iPhone → Mac. This is a closed list on purpose: the Mac never runs arbitrary commands sent
/// over the network.
public enum ControlMessage: Codable, Equatable, Sendable {
    case hello(phoneName: String, protocolVersion: Int)
    case pointerMove(dx: Double, dy: Double)
    case click(MouseButton)
    case buttonDown(MouseButton)
    case buttonUp(MouseButton)
    case scroll(dx: Double, dy: Double)
    case key(Key, modifiers: [Modifier])
    case text(String)
    case media(MediaKey)
}

/// Mac → iPhone.
public enum MacMessage: Codable, Equatable, Sendable {
    case welcome(macName: String, protocolVersion: Int)
    /// The Mac cannot inject input until Accessibility is granted.
    case accessibilityRequired
}

public enum MouseButton: String, Codable, Sendable {
    case left, right
}

public enum Modifier: String, Codable, Sendable, CaseIterable {
    case command, option, control, shift
}

public enum Key: String, Codable, Sendable, CaseIterable {
    case returnKey, delete, forwardDelete, escape, tab, space
    case left, right, up, down
    case home, end, pageUp, pageDown
}

public enum MediaKey: String, Codable, Sendable, CaseIterable {
    case playPause, next, previous
    case volumeUp, volumeDown, mute
    case brightnessUp, brightnessDown
}
