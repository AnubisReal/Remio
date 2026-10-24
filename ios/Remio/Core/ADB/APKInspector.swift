import Foundation
import Compression

struct APKMetadata: Sendable, Equatable {
    let package: String
    let minSDK: Int
    let version: String?
    let split: String?
}

/// Bounded ZIP/Android binary XML inspection. Android still verifies signatures at installation.
enum APKInspector {
    static func inspect(_ apk: Data, expectedPackage: String? = nil, sdk: Int? = nil) throws -> APKMetadata {
        let xml = try manifest(in: apk)
        let metadata = try parse(xml)
        if let expectedPackage, metadata.package != expectedPackage {
            throw ADBToolError.refused(String(localized: "El APK no corresponde al paquete declarado en la copia."))
        }
        if let sdk, metadata.minSDK > sdk {
            throw ADBToolError.refused(String(localized: "El APK requiere Android API \(metadata.minSDK); el Portal tiene API \(sdk)."))
        }
        return metadata
    }

    static func manifest(in apk: Data) throws -> Data {
        guard apk.count >= 22, apk.count <= ADBTools.limit else { throw ADBToolError.invalidData }
        let reader = Bytes(data: apk)
        var eocd: Int?
        for at in stride(from: apk.count - 22, through: max(0, apk.count - 65557), by: -1) {
            if (try reader.u32(at)) == 0x06054b50, at + 22 + (try reader.u16(at + 20)) == apk.count { eocd = at; break }
        }
        guard let end = eocd, (try reader.u16(end + 4)) == 0, (try reader.u16(end + 6)) == 0,
              (try reader.u16(end + 8)) == (try reader.u16(end + 10)) else { throw ADBToolError.invalidData }
        let count = (try reader.u16(end + 10)), centralSize = (try reader.u32(end + 12))
        var at = (try reader.u32(end + 16))
        guard count > 0, count < 65535, centralSize < end, at + centralSize == end else { throw ADBToolError.invalidData }
        let centralStart = at
        var result: Data?
        for _ in 0..<count {
            guard at + 46 <= end, (try reader.u32(at)) == 0x02014b50 else { throw ADBToolError.invalidData }
            let nameLength = (try reader.u16(at + 28)), extra = (try reader.u16(at + 30)), comment = (try reader.u16(at + 32))
            let next = at + 46 + nameLength + extra + comment
            guard next <= end, nameLength <= 4096 else { throw ADBToolError.invalidData }
            let name = try reader.slice(at + 46, nameLength)
            if name == Data("AndroidManifest.xml".utf8) {
                guard result == nil else { throw ADBToolError.invalidData }
                let flags = (try reader.u16(at + 8)), method = (try reader.u16(at + 10))
                let packed = (try reader.u32(at + 20)), size = (try reader.u32(at + 24)), local = (try reader.u32(at + 42))
                guard flags & 1 == 0, method == 0 || method == 8, size > 0, size <= 4 * 1024 * 1024,
                      packed > 0, packed <= 4 * 1024 * 1024, local + 30 <= centralStart,
                      (try reader.u32(local)) == 0x04034b50, (try reader.u16(local + 8)) == method,
                      (try reader.u16(local + 6)) & 1 == 0 else { throw ADBToolError.invalidData }
                let localName = (try reader.u16(local + 26)), localExtra = (try reader.u16(local + 28))
                guard try reader.slice(local + 30, localName) == name else { throw ADBToolError.invalidData }
                let start = local + 30 + localName + localExtra
                guard start + packed <= centralStart else { throw ADBToolError.invalidData }
                let bytes = try reader.slice(start, packed)
                let xml: Data
                if method == 0 {
                    guard packed == size else { throw ADBToolError.invalidData }; xml = bytes
                } else {
                    var output = Data(count: size + 1)
                    let decoded = output.withUnsafeMutableBytes { destination in
                        bytes.withUnsafeBytes { source in
                            compression_decode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, size + 1,
                                source.bindMemory(to: UInt8.self).baseAddress!, bytes.count, nil, COMPRESSION_ZLIB)
                        }
                    }
                    guard decoded == size else { throw ADBToolError.invalidData }
                    xml = Data(output.prefix(size))
                }
                guard ToolkitArchive.crc(xml) == UInt32((try reader.u32(at + 16))) else { throw ADBToolError.invalidData }
                result = xml
            }
            at = next
        }
        guard at == end, let result else { throw ADBToolError.refused(String(localized: "El archivo no contiene un manifiesto APK válido.")) }
        return result
    }

    static func parse(_ data: Data) throws -> APKMetadata {
        let b = Bytes(data: data)
        guard data.count >= 8, (try b.u16(0)) == 3, (try b.u16(2)) == 8, (try b.u32(4)) == data.count else { throw ADBToolError.invalidData }
        var decodedStringBytes = 0
        var strings: [String] = [], package: String?, minimum = 1, version: String?, split: String?
        var at = 8, depth = 0, rootSeen = false, sdkSeen = false
        var elements: [Int] = []
        while at < data.count {
            let type = (try b.u16(at)), header = (try b.u16(at + 2)), size = (try b.u32(at + 4))
            guard header >= 8, size >= header, at + size <= data.count else { throw ADBToolError.invalidData }
            if type == 1 {
                guard strings.isEmpty, header >= 28 else { throw ADBToolError.invalidData }
                let count = (try b.u32(at + 8)), styleCount = (try b.u32(at + 12)), flags = (try b.u32(at + 16))
                let start = (try b.u32(at + 20)), stylesStart = (try b.u32(at + 24))
                let stringEnd = stylesStart == 0 ? at + size : at + stylesStart
                guard count <= 50000, styleCount <= 50000, header + (count + styleCount) * 4 <= start,
                      start <= size, stringEnd <= at + size, stringEnd >= at + start else { throw ADBToolError.invalidData }
                for index in 0..<count {
                    var pos = at + start + (try b.u32(at + header + index * 4))
                    guard pos < stringEnd else { throw ADBToolError.invalidData }
                    func length(_ wide: Bool) throws -> Int {
                        let first = wide ? (try b.u16(pos)) : (try b.u8(pos)); pos += wide ? 2 : 1
                        let mask = wide ? 0x8000 : 0x80
                        if first & mask != 0 {
                            let next = wide ? (try b.u16(pos)) : (try b.u8(pos)); pos += wide ? 2 : 1
                            return ((first & ~mask) << (wide ? 16 : 8)) | next
                        }
                        return first
                    }
                    let utf8 = flags & 0x100 != 0
                    let units = try length(!utf8)
                    let bytes = try utf8 ? length(false) : units * 2
                    let terminator = utf8 ? 1 : 2
                    decodedStringBytes += bytes
                    guard bytes <= 65536, decodedStringBytes <= 8 * 1024 * 1024, pos + bytes + terminator <= stringEnd,
                          (try b.u8(pos + bytes)) == 0 else { throw ADBToolError.invalidData }
                    if !utf8 { guard (try b.u8(pos + bytes + 1)) == 0 else { throw ADBToolError.invalidData } }
                    guard let text = String(data: try b.slice(pos, bytes), encoding: utf8 ? .utf8 : .utf16LittleEndian) else { throw ADBToolError.invalidData }
                    strings.append(text)
                }
            } else if type == 0x102 {
                guard header >= 16, at + header + 20 <= at + size, !strings.isEmpty else { throw ADBToolError.invalidData }
                let ext = at + header
                func string(_ index: Int) throws -> String {
                    guard index >= 0, index < strings.count else { throw ADBToolError.invalidData }; return strings[index]
                }
                let name = try string((try b.u32(ext + 4))), offset = (try b.u16(ext + 8))
                let stride = (try b.u16(ext + 10)), count = (try b.u16(ext + 12))
                guard offset >= 20, stride >= 20, count <= 1000, ext + offset + stride * count <= at + size else { throw ADBToolError.invalidData }
                if depth == 0 { guard !rootSeen, name == "manifest" else { throw ADBToolError.invalidData }; rootSeen = true }
                for i in 0..<count {
                    let attr = ext + offset + i * stride
                    let namespace = (try b.u32(attr)), key = try string((try b.u32(attr + 4))), raw = (try b.u32(attr + 8))
                    guard (try b.u16(attr + 12)) == 8 else { throw ADBToolError.invalidData }
                    let kind = (try b.u8(attr + 15)), value = (try b.u32(attr + 16))
                    let text: String?
                    if kind == 3 { text = try string(value) }
                    else if raw != 0xffffffff { text = try string(raw) }
                    else { text = nil }
                    let android = try namespace != 0xffffffff && string(namespace) == "http://schemas.android.com/apk/res/android"
                    if depth == 0, key == "package", namespace == 0xffffffff { guard package == nil, let text else { throw ADBToolError.invalidData }; package = try ADBTools.package(text) }
                    if depth == 0, key == "split", namespace == 0xffffffff { split = text }
                    if depth == 0, key == "versionName", android { version = text }
                    if depth == 1, name == "uses-sdk", key == "minSdkVersion", android {
                        guard !sdkSeen else { throw ADBToolError.invalidData }; sdkSeen = true
                        if kind == 0x10 || kind == 0x11 { minimum = value }
                        else if let text, let number = Int(text) { minimum = number }
                        else { throw ADBToolError.refused(String(localized: "El APK requiere una versión preliminar de Android no compatible.")) }
                    }
                }
                elements.append(try b.u32(ext + 4)); depth += 1
            } else if type == 0x103 {
                guard header >= 16, at + header + 8 <= at + size, depth > 0,
                      try b.u32(at + header + 4) == elements.last else { throw ADBToolError.invalidData }
                elements.removeLast(); depth -= 1
            }
            at += size
        }
        guard rootSeen, depth == 0, let package, minimum > 0, minimum <= 10000 else { throw ADBToolError.invalidData }
        return APKMetadata(package: package, minSDK: minimum, version: version, split: split)
    }

    private struct Bytes {
        let data: Data
        func slice(_ at: Int, _ size: Int) throws -> Data {
            guard at >= 0, size >= 0, at <= data.count, size <= data.count - at else { throw ADBToolError.invalidData }
            return data.subdata(in: (data.startIndex + at)..<(data.startIndex + at + size))
        }
        func u8(_ at: Int) throws -> Int {
            guard at >= 0, at < data.count else { throw ADBToolError.invalidData }; return Int(data[data.startIndex + at])
        }
        func u16(_ at: Int) throws -> Int { try u8(at) | u8(at + 1) << 8 }
        func u32(_ at: Int) throws -> Int { try u16(at) | u16(at + 2) << 16 }
    }
}

extension ADBTools {
    static func installationError(_ response: String) -> String {
        let reasons: [(String, String)] = [
            ("INSTALL_FAILED_VERSION_DOWNGRADE", String(localized: "El Portal ya tiene una versión más reciente de esta app.")),
            ("INSTALL_FAILED_UPDATE_INCOMPATIBLE", String(localized: "La firma del APK no coincide con la app instalada. No se ha eliminado la app existente.")),
            ("INSTALL_FAILED_OLDER_SDK", String(localized: "El APK requiere una versión de Android más reciente.")),
            ("INSTALL_FAILED_NO_MATCHING_ABIS", String(localized: "El APK no es compatible con la arquitectura del Portal.")),
            ("INSTALL_FAILED_INSUFFICIENT_STORAGE", String(localized: "No hay suficiente espacio libre en el Portal.")),
            ("INSTALL_PARSE_FAILED", String(localized: "El Portal no pudo interpretar el APK. Comprueba que el archivo esté completo.")),
            ("INSTALL_FAILED_INVALID_APK", String(localized: "El Portal rechazó el APK porque no es válido.")),
            ("SecurityException", String(localized: "El Portal bloqueó la instalación por seguridad."))
        ]
        return reasons.first(where: { response.contains($0.0) })?.1 ?? String(response.prefix(800))
    }
}
