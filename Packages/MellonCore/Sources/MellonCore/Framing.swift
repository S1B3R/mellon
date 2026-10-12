import Foundation

/// Messages travel as JSON with a 4-byte big-endian length prefix.
public enum Frame {
    /// Generous for control messages; anything larger is treated as an attack and drops the connection.
    public static let maxLength = 64 * 1024

    public enum Error: Swift.Error, Equatable {
        case tooLarge(Int)
    }

    public static func encode<T: Encodable>(_ message: T) throws -> Data {
        let body = try JSONEncoder().encode(message)
        guard body.count <= maxLength else { throw Error.tooLarge(body.count) }
        var length = UInt32(body.count).bigEndian
        return Data(bytes: &length, count: 4) + body
    }
}

/// Reassembles frames from an arbitrarily chunked TCP stream.
public struct FrameDecoder: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(0) { $0 << 8 | Int($1) }
            guard length <= Frame.maxLength else { throw Frame.Error.tooLarge(length) }
            guard buffer.count >= 4 + length else { break }
            frames.append(Data(buffer.dropFirst(4).prefix(length)))
            buffer = Data(buffer.dropFirst(4 + length))
        }
        return frames
    }
}
