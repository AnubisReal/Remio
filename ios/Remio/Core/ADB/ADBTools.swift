import Foundation

enum ADBToolError: Error, LocalizedError {
    case disconnected, busy, invalidData, refused(String), tooLarge
    var errorDescription: String? {
        switch self {
        case .disconnected: "ADB no está conectado."
        case .busy: "Espera a que termine la operación actual."
        case .invalidData: "El Portal devolvió datos que no se pueden validar."
        case .refused(let reason): reason
        case .tooLarge: "El archivo supera el límite de 256 MB por transferencia."
        }
    }
}

enum ADBTools {
    static let limit = 256 * 1024 * 1024
    static let updates = ["com.facebook.aloha.alohaotasetup", "com.facebook.aloha.otaui"]
    static func package(_ value: String) throws -> String {
        guard !value.isEmpty, value.utf8.count <= 255, value.contains("."),
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 46 || $0 == 95 }) else { throw ADBToolError.invalidData }
        return value
    }
    static func quote(_ value: String) throws -> String {
        guard !value.contains("\0"), !value.contains("\n"), !value.contains("\r"), value.utf8.count < 4096 else { throw ADBToolError.invalidData }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    static func sync(_ name: String, _ payload: Data, value: UInt32? = nil) -> Data {
        var result = Data(name.utf8)
        var size = (value ?? UInt32(payload.count)).littleEndian
        withUnsafeBytes(of: &size) { result.append(contentsOf: $0) }
        result.append(payload)
        return result
    }
    static func number(_ data: Data, at offset: Int) -> Int {
        let bytes = Array(data[offset..<offset+4])
        return (0..<4).reduce(0) { $0 | Int(bytes[$1]) << (8 * $1) }
    }
    static func syncResult(_ input: Data, receiving: Bool) throws -> Data? {
        try ADBSyncDecoder(receiving: receiving).feed(input)
    }

}

struct PortalPackage: Identifiable, Hashable, Codable {
    let packageName: String
    var id: String { packageName }
}

struct ToolkitHistory: Identifiable, Codable {
    let id: UUID
    let date: Date
    let action: String
    let success: Bool
}

/// Incremental parser: a large pull never reparses all previous chunks.
final class ADBSyncDecoder {
    let receiving: Bool
    private var pending = Data()
    private var output = Data()
    init(receiving: Bool) { self.receiving = receiving }
    func feed(_ bytes: Data) throws -> Data? {
        pending.append(bytes)
        while pending.count >= 8 {
            let name = String(data: pending.prefix(4), encoding: .ascii)
            let size = ADBTools.number(pending, at: 4)
            if receiving, name == "DONE" { return output }
            if !receiving, name == "OKAY", size == 0 { return Data() }
            guard name == "DATA" || name == "FAIL", size <= (name == "DATA" ? 65536 : 4096) else { throw ADBToolError.invalidData }
            guard pending.count >= 8 + size else { return nil }
            let data = Data(pending[8..<8+size])
            if name == "FAIL" { throw ADBToolError.refused(String(decoding: data, as: UTF8.self)) }
            guard receiving, output.count + size <= ADBTools.limit else { throw ADBToolError.tooLarge }
            output.append(data)
            pending = Data(pending.dropFirst(8+size))
        }
        return nil
    }
}

struct SavedADBPortal: Codable, Identifiable {
    let endpoint: PortalEndpoint
    var name: String
    var id: String { endpoint.id }
}
