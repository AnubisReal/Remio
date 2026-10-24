import Foundation
import Compression

enum ToolkitArchive {
    static let maxBytes = 256 * 1024 * 1024
    static func crc(_ data: Data) -> UInt32 {
        var value = UInt32.max
        for byte in data {
            value ^= UInt32(byte)
            for _ in 0..<8 { value = (value >> 1) ^ (value & 1 == 1 ? 0xedb88320 : 0) }
        }
        return value ^ UInt32.max
    }
    static func safe(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0") &&
            path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    private static func append(_ value: UInt32, bytes: Int, to data: inout Data) {
        for index in 0..<bytes { data.append(UInt8(truncatingIfNeeded: value >> (index * 8))) }
    }
    static func encode(_ entries: [String: Data]) throws -> Data {
        guard entries.count <= 500 else { throw ADBToolError.invalidData }
        var archive = Data(), central = Data()
        for name in entries.keys.sorted() {
            let data = entries[name]!
            guard safe(name), name.utf8.count <= 1024, data.count <= maxBytes,
                  archive.count + central.count + data.count < maxBytes else { throw ADBToolError.tooLarge }
            let path = Data(name.utf8), offset = archive.count, checksum = crc(data)
            for (value, size) in [(UInt32(0x04034b50),4),(20,2),(0x800,2),(0,2),(0,2),(0,2),(checksum,4),(UInt32(data.count),4),(UInt32(data.count),4),(UInt32(path.count),2),(0,2)] {
                append(value, bytes: size, to: &archive)
            }
            archive.append(path); archive.append(data)
            for (value, size) in [(UInt32(0x02014b50),4),(20,2),(20,2),(0x800,2),(0,2),(0,2),(0,2),(checksum,4),(UInt32(data.count),4),(UInt32(data.count),4),(UInt32(path.count),2),(0,2),(0,2),(0,2),(0,2),(0,4),(UInt32(offset),4)] {
                append(value, bytes: size, to: &central)
            }
            central.append(path)
        }
        let start = archive.count
        archive.append(central)
        for (value, size) in [(UInt32(0x06054b50),4),(0,2),(0,2),(UInt32(entries.count),2),(UInt32(entries.count),2),(UInt32(central.count),4),(UInt32(start),4),(0,2)] {
            append(value, bytes: size, to: &archive)
        }
        return archive
    }
    static func decode(_ archive: Data) throws -> [String: Data] {
        guard archive.count >= 22, archive.count <= maxBytes else { throw ADBToolError.tooLarge }
        let b = Array(archive)
        func number(_ at: Int, _ size: Int) throws -> Int {
            guard at >= 0, at + size <= b.count else { throw ADBToolError.invalidData }
            return (0..<size).reduce(0) { $0 | Int(b[at+$1]) << ($1*8) }
        }
        var end: Int?
        for offset in stride(from: b.count-22, through: max(0,b.count-65557), by: -1) {
            if try number(offset,4) == 0x06054b50, offset+22+(try number(offset+20,2)) == b.count { end = offset; break }
        }
        guard let end, try number(end+4,2) == 0, try number(end+6,2) == 0 else { throw ADBToolError.invalidData }
        let count = try number(end+10,2), centralSize = try number(end+12,4)
        var offset = try number(end+16,4)
        guard count <= 500, offset + centralSize == end else { throw ADBToolError.invalidData }
        var result: [String: Data] = [:], total = 0
        for _ in 0..<count {
            guard try number(offset,4) == 0x02014b50 else { throw ADBToolError.invalidData }
            let flags = try number(offset+8,2), method = try number(offset+10,2), checksum = try number(offset+16,4)
            let packed = try number(offset+20,4), size = try number(offset+24,4)
            let nameSize = try number(offset+28,2), extra = try number(offset+30,2), comment = try number(offset+32,2)
            let local = try number(offset+42,4)
            guard flags & 1 == 0, method == 0 || method == 8, size <= maxBytes, total + size <= maxBytes,
                  nameSize > 0, nameSize <= 1024, offset+46+nameSize+extra+comment <= end,
                  try number(local,4) == 0x04034b50 else { throw ADBToolError.invalidData }
            guard let name = String(bytes: b[offset+46..<offset+46+nameSize], encoding: .utf8), safe(name), result[name] == nil else { throw ADBToolError.invalidData }
            let localNameSize = try number(local+26,2), localExtra = try number(local+28,2)
            let start = local+30+localNameSize+localExtra
            guard localNameSize == nameSize, local+30+nameSize <= b.count,
                  Array(b[local+30..<local+30+nameSize]) == Array(name.utf8), start+packed <= (try number(end+16,4)) else { throw ADBToolError.invalidData }
            let compressed = Data(b[start..<start+packed])
            let data: Data
            if method == 0 { guard size == packed else { throw ADBToolError.invalidData }; data = compressed }
            else {
                guard packed > 0 else { throw ADBToolError.invalidData }
                var output = Data(count: max(1,size))
                let decoded = output.withUnsafeMutableBytes { destination in
                    compressed.withUnsafeBytes { source in
                        compression_decode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, max(1,size),
                                                  source.bindMemory(to: UInt8.self).baseAddress!, compressed.count, nil, COMPRESSION_ZLIB)
                    }
                }
                guard decoded == size else { throw ADBToolError.invalidData }
                data = Data(output.prefix(size))
            }
            guard crc(data) == UInt32(checksum) else { throw ADBToolError.invalidData }
            result[name] = data; total += size
            offset += 46+nameSize+extra+comment
        }
        return result
    }
}

struct ToolkitBackup: Codable, Sendable {
    struct Device: Codable, Sendable { let manufacturer: String; let model: String; let sdk: String }
    struct App: Codable, Sendable { let packageName: String; let files: [String] }
    let formatVersion: Int
    let createdAt: Int64
    let device: Device
    let settings: [String: String]
    let apps: [App]

    static func inspect(_ entries: [String: Data]) throws -> ToolkitBackup {
        guard let data = entries["manifest.json"], data.count <= 1_048_576 else { throw ADBToolError.invalidData }
        let manifest = try JSONDecoder().decode(ToolkitBackup.self, from: data)
        guard manifest.formatVersion == 1, manifest.apps.count <= 200,
              (0...4_102_444_800_000).contains(manifest.createdAt),
              !manifest.device.model.isEmpty, manifest.device.model.count <= 128,
              let sdk = Int(manifest.device.sdk), (1...10000).contains(sdk),
              !manifest.apps.isEmpty || !manifest.settings.isEmpty,
              Set(manifest.apps.map(\.packageName)).count == manifest.apps.count else { throw ADBToolError.invalidData }
        for key in ADBTools.backupSettings {
            if let value = manifest.settings["system." + key], ADBTools.backupSetting(key, value: value) == nil {
                throw ADBToolError.invalidData
            }
        }
        for app in manifest.apps {
            _ = try ADBTools.package(app.packageName)
            guard !app.files.isEmpty, app.files.count <= 50, Set(app.files).count == app.files.count else { throw ADBToolError.invalidData }
            for file in app.files {
                guard !file.contains("/"), file.hasSuffix(".apk"), let apk = entries["apps/\(app.packageName)/\(file)"],
                      apk.starts(with: [0x50,0x4b,0x03,0x04]) else { throw ADBToolError.invalidData }
                _ = try APKInspector.inspect(apk, expectedPackage: app.packageName)
            }
        }
        return manifest
    }
}
