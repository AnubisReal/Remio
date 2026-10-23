import Foundation

/// Bounded classic ADB packets shared by authentication and serialized tool streams.
enum ADBHandshake {
    static let connect: UInt32 = 0x4e584e43
    static let open: UInt32 = 0x4e45504f
    static let okay: UInt32 = 0x59414b4f
    static let write: UInt32 = 0x45545257
    static let close: UInt32 = 0x45534c43
    static let auth: UInt32 = 0x48545541

    static func hello() -> Data {
        packet(command: connect, arg0: 0x01000000, arg1: 4096, payload: Data("host::\0".utf8))
    }

    static func packet(command: UInt32, arg0: UInt32 = 0, arg1: UInt32 = 0, payload: Data) -> Data {
        var packet = Data()
        for word: UInt32 in [command, arg0, arg1, UInt32(payload.count),
                             payload.reduce(UInt32(0)) { $0 + UInt32($1) }, command ^ 0xffffffff] {
            var little = word.littleEndian
            withUnsafeBytes(of: &little) { packet.append(contentsOf: $0) }
        }
        packet.append(payload)
        return packet
    }

    static func response(_ header: Data) throws -> (command: UInt32, length: Int, checksum: UInt32, arg0: UInt32, arg1: UInt32) {
        guard header.count == 24 else { throw PortalError.incompatible }
        let bytes = Array(header)
        func word(_ offset: Int) -> UInt32 {
            (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
        }
        let command = word(0)
        guard word(20) == command ^ 0xffffffff, word(12) <= 4096,
              command == connect || [okay, write, close].contains(command) || (command == auth && word(4) == 1 && word(12) == 20) else {
            throw PortalError.incompatible
        }
        return (command, Int(word(12)), word(16), word(4), word(8))
    }
}
