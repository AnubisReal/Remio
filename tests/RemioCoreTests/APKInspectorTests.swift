import Foundation
import Compression
import Testing
@testable import RemioCore

private func bytes(_ number: Int, _ count: Int = 4) -> Data {
    Data((0..<count).map { UInt8(truncatingIfNeeded: number >> ($0 * 8)) })
}

private func xmlFixture(package: String = "com.example.test", sdk: Int = 29, utf8: Bool = true, split: String? = nil) -> Data {
    let names = ["manifest", "package", package, "uses-sdk", "minSdkVersion", "http://schemas.android.com/apk/res/android", "split", split ?? "", "versionName", "1.2"]
    var strings = Data(), offsets = Data()
    for name in names {
        offsets.append(bytes(strings.count))
        if utf8 {
            strings.append(UInt8(name.utf16.count)); strings.append(UInt8(name.utf8.count)); strings.append(Data(name.utf8)); strings.append(0)
        } else {
            strings.append(bytes(name.utf16.count, 2)); strings.append(name.data(using: .utf16LittleEndian)!); strings.append(bytes(0, 2))
        }
    }
    while strings.count % 4 != 0 { strings.append(0) }
    var pool = bytes(1, 2) + bytes(28, 2) + bytes(28 + offsets.count + strings.count)
    pool += bytes(names.count) + bytes(0) + bytes(utf8 ? 0x100 : 0) + bytes(28 + offsets.count) + bytes(0) + offsets + strings
    func attribute(_ namespace: Int, _ key: Int, _ value: Int, _ type: Int) -> Data {
        bytes(namespace) + bytes(key) + bytes(type == 3 ? value : 0xffffffff) + bytes(8, 2) + bytes(0, 1) + bytes(type, 1) + bytes(value)
    }
    func start(_ name: Int, _ attributes: [Data]) -> Data {
        var node = bytes(0x102, 2) + bytes(16, 2) + bytes(36 + attributes.count * 20) + bytes(1) + bytes(0xffffffff)
        node += bytes(0xffffffff) + bytes(name) + bytes(20, 2) + bytes(20, 2) + bytes(attributes.count, 2) + bytes(0, 2) + bytes(0, 2) + bytes(0, 2)
        for attr in attributes { node.append(attr) }
        return node
    }
    func end(_ name: Int) -> Data {
        bytes(0x103, 2) + bytes(16, 2) + bytes(24) + bytes(1) + bytes(0xffffffff) + bytes(0xffffffff) + bytes(name)
    }
    var attributes = [attribute(0xffffffff, 1, 2, 3), attribute(5, 8, 9, 3)]
    if split != nil { attributes.append(attribute(0xffffffff, 6, 7, 3)) }
    let nodes = pool + start(0, attributes) + start(3, [attribute(5, 4, sdk, 0x10)]) + end(3) + end(0)
    return bytes(3, 2) + bytes(8, 2) + bytes(nodes.count + 8) + nodes
}

@Test(arguments: [true, false]) func apkReadsBinaryManifestBothEncodings(utf8: Bool) throws {
    let xml = xmlFixture(utf8: utf8)
    let apk = try ToolkitArchive.encode(["AndroidManifest.xml": xml, "classes.dex": Data([1, 2, 3])])
    let info = try APKInspector.inspect(apk, expectedPackage: "com.example.test", sdk: 29)
    #expect(info.package == "com.example.test")
    #expect(info.minSDK == 29)
    #expect(info.version == "1.2")
    #expect(info.split == nil)
}

@Test func apkRejectsPackageMismatchAndNewerSDK() throws {
    let apk = try ToolkitArchive.encode(["AndroidManifest.xml": xmlFixture()])
    #expect(throws: (any Error).self) { try APKInspector.inspect(apk, expectedPackage: "com.other.app") }
    #expect(throws: (any Error).self) { try APKInspector.inspect(apk, sdk: 28) }
    let split = try ToolkitArchive.encode(["AndroidManifest.xml": xmlFixture(split: "config.en")])
    #expect(try APKInspector.inspect(split).split == "config.en")
}

@Test func apkRejectsTruncationCorruptionAndMissingManifest() throws {
    let apk = try ToolkitArchive.encode(["AndroidManifest.xml": xmlFixture()])
    for count in [0, 7, 21, apk.count / 2, apk.count - 1] {
        #expect(throws: (any Error).self) { try APKInspector.inspect(Data(apk.prefix(count))) }
    }
    var corrupt = apk; corrupt[55] ^= 1
    #expect(throws: (any Error).self) { try APKInspector.inspect(corrupt) }
    #expect(throws: (any Error).self) { try APKInspector.inspect(ToolkitArchive.encode(["classes.dex": Data([0])])) }
    var xml = xmlFixture(); xml[4] = 0
    #expect(throws: (any Error).self) { try APKInspector.parse(xml) }
}

@Test func backupValidatesAPKPackageAndAcceptsSettingsOnly() throws {
    let manifest = ToolkitBackup(formatVersion: 1, createdAt: 0, device: .init(manufacturer: "Facebook", model: "Portal+", sdk: "29"), settings: ["system.screen_brightness": "50"], apps: [])
    #expect(try ToolkitBackup.inspect(["manifest.json": JSONEncoder().encode(manifest)]).apps.isEmpty)
    let wrong = ToolkitBackup(formatVersion: 1, createdAt: 0, device: manifest.device, settings: [:], apps: [.init(packageName: "com.wrong.app", files: ["base.apk"])])
    let entries = ["manifest.json": try JSONEncoder().encode(wrong), "apps/com.wrong.app/base.apk": try ToolkitArchive.encode(["AndroidManifest.xml": xmlFixture()])]
    #expect(throws: (any Error).self) { try ToolkitBackup.inspect(entries) }
}

@Test func scanStaysPrivateWithinSubnetAndSkipsLocalAddress() throws {
    let hosts = try ADBTools.scanHosts(address: "192.168.0.132", mask: "255.255.255.0")
    #expect(hosts.count == 253)
    #expect(!hosts.contains("192.168.0.132"))
    #expect(!hosts.contains("192.168.0.0") && !hosts.contains("192.168.0.255"))
    #expect(try ADBTools.scanHosts(address: "10.0.0.5", mask: "255.255.255.252") == ["10.0.0.6"])
    #expect(throws: (any Error).self) { try ADBTools.scanHosts(address: "8.8.8.8", mask: "255.255.255.0") }
    #expect(throws: (any Error).self) { try ADBTools.scanHosts(address: "10.0.0.5", mask: "255.0.255.0") }
}

@Test func installFailuresHaveActionableMessagesWithoutAutoRemoval() {
    let message = ADBTools.installationError("Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE]")
    #expect(!message.contains("INSTALL_FAILED"))
    #expect(ADBTools.installationError("Unexpected failure") == "Unexpected failure")
}


@Test func restoreStopsAfterConsecutiveFailuresAndNeverAppliesSettingsAfterPartialRestore() {
    var result = RestoreProgress(total: 6)
    result.record(success: false); result.record(success: false)
    #expect(!result.shouldStop)
    result.record(success: true)
    #expect(result.consecutiveFailures == 0)
    result.record(success: false); result.record(success: false); result.record(success: false)
    #expect(result.shouldStop && !result.canRestoreSettings)
    #expect(result.installed == 1 && result.failed == 5 && result.skipped == 0)
    #expect(RestoreProgress(total: 0).canRestoreSettings)
    var success = RestoreProgress(total: 1); success.record(success: true)
    #expect(success.canRestoreSettings)
}

@Test func apkRejectsTamperedCRCAndEncryptedManifest() throws {
    let original = try ToolkitArchive.encode(["AndroidManifest.xml": xmlFixture()])
    let signature = Data([0x50, 0x4b, 0x01, 0x02])
    let central = try #require(original.range(of: signature)?.lowerBound)
    var crc = original; crc[central + 16] ^= 1
    #expect(throws: (any Error).self) { try APKInspector.inspect(crc) }
    var encrypted = original; encrypted[central + 8] |= 1
    #expect(throws: (any Error).self) { try APKInspector.inspect(encrypted) }
    var offset = original
    offset.replaceSubrange(central + 42..<central + 46, with: bytes(0xffffffff))
    #expect(throws: (any Error).self) { try APKInspector.inspect(offset) }
}

@Test func apkAcceptsDataWithNonzeroStartIndex() throws {
    let apk = try ToolkitArchive.encode(["AndroidManifest.xml": xmlFixture()])
    let sliced = (Data([0, 0]) + apk).dropFirst(2)
    #expect(try APKInspector.inspect(sliced).package == "com.example.test")
}


@Test func apkReadsDeflatedBinaryManifest() throws {
    let xml = xmlFixture()
    var buffer = Data(count: 8192)
    let packed = buffer.withUnsafeMutableBytes { destination in
        xml.withUnsafeBytes { source in
            compression_encode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, 8192,
                source.bindMemory(to: UInt8.self).baseAddress!, xml.count, nil, COMPRESSION_ZLIB)
        }
    }
    #expect(packed > 0)
    let name = Data("AndroidManifest.xml".utf8), crc = Int(ToolkitArchive.crc(xml))
    var apk = Data()
    for (value, width) in [(0x04034b50, 4), (20, 2), (0, 2), (8, 2), (0, 4), (crc, 4), (packed, 4), (xml.count, 4), (name.count, 2), (0, 2)] { apk.append(bytes(value, width)) }
    apk.append(name); apk.append(buffer.prefix(packed))
    let centralStart = apk.count
    var central = Data()
    for (value, width) in [(0x02014b50, 4), (20, 2), (20, 2), (0, 2), (8, 2), (0, 4), (crc, 4), (packed, 4), (xml.count, 4), (name.count, 2), (0, 2), (0, 2), (0, 2), (0, 2), (0, 4), (0, 4)] { central.append(bytes(value, width)) }
    central.append(name); apk.append(central)
    for (value, width) in [(0x06054b50, 4), (0, 2), (0, 2), (1, 2), (1, 2), (central.count, 4), (centralStart, 4), (0, 2)] { apk.append(bytes(value, width)) }
    #expect(try APKInspector.inspect(apk).package == "com.example.test")
}

@Test func backupSettingValidationRejectsInvalidValuesAndUnknownKeys() {
    #expect(ADBTools.backupSetting("screen_brightness", value: "50") == "50")
    #expect(ADBTools.backupSetting("screen_brightness", value: "256") == nil)
    #expect(ADBTools.backupSetting("screen_off_timeout", value: "-1") == nil)
    #expect(ADBTools.backupSetting("screen_off_timeout", value: "300000") == "300000")
    #expect(ADBTools.backupSetting("user_rotation", value: "4") == nil)
    #expect(ADBTools.backupSetting("accelerometer_rotation", value: "1.0") == nil)
    #expect(ADBTools.backupSetting("volume_music", value: "5; reboot") == nil)
    #expect(ADBTools.backupSetting("unknown", value: "1") == nil)
}
