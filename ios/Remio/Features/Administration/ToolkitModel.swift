import Foundation
import Observation

@MainActor @Observable
final class ToolkitModel {
    private(set) var busy = false
    private(set) var progress = ""
    var error: String?
    private(set) var packages: [PortalPackage] = []
    private(set) var information: [String: String] = [:]
    private(set) var history: [ToolkitHistory] = []
    private(set) var otaPackages: [String] = []
    private(set) var disabledOTA: [String] = []
    let adb: AdministrationModel

    init(adb: AdministrationModel) {
        self.adb = adb
        if let data = UserDefaults.standard.data(forKey: "remio.tools.history"),
           let entries = try? JSONDecoder().decode([ToolkitHistory].self, from: data) { history = entries }
    }

    func perform(_ activity: ToolkitActivity, requiresPortal: Bool = true, operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; error = nil; progress = activity.title
        Task {
            defer { busy = false; progress = "" }
            do {
                if requiresPortal { try await validatePortal() }
                try await operation()
                record(activity, success: true)
            }
            catch { self.error = error.localizedDescription; record(activity, success: false) }
        }
    }

    func setProgress(_ value: String) { progress = value }

    private func record(_ activity: ToolkitActivity, success: Bool) {
        history.insert(ToolkitHistory(id: UUID(), date: .now, action: activity.title, success: success, activity: activity), at: 0)
        history = Array(history.prefix(100))
        if let data = try? JSONEncoder().encode(history) { UserDefaults.standard.set(data, forKey: "remio.tools.history") }
    }

    func clearHistory() { history = []; UserDefaults.standard.removeObject(forKey: "remio.tools.history") }

    private func validatePortal() async throws {
        let manufacturer = try await shell("getprop ro.product.manufacturer").lowercased()
        let model = try await shell("getprop ro.product.model").lowercased()
        let device = try await shell("getprop ro.product.device").lowercased()
        guard manufacturer.contains("facebook") || manufacturer.contains("meta") ||
              model.contains("portal") || ["cipher", "aloha", "aloha_plus", "woody", "cambria", "ripley"].contains(device) else {
            throw ADBToolError.refused(String(localized: "El equipo ADB no se identifica como un Portal."))
        }
    }

    private func shell(_ command: String) async throws -> String {
        let marker = "REMIO_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let wrapped = command + "; printf '\\n" + marker + "%s\\n' \"$?\""
        let data = try await adb.service("shell:" + wrapped)
        guard data.count <= 4 * 1024 * 1024, let text = String(data: data, encoding: .utf8),
              let range = text.range(of: "\n" + marker, options: .backwards) else { throw ADBToolError.invalidData }
        let code = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let output = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard code == "0" else { throw ADBToolError.refused(String(output.prefix(800))) }
        return output
    }

    func refreshPackages() async throws {
        let text = try await shell("pm list packages -3")
        packages = try text.split(whereSeparator: \.isNewline).filter { $0.hasPrefix("package:") }.map {
            PortalPackage(packageName: try ADBTools.package(String($0.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)))
        }.sorted { $0.packageName < $1.packageName }
    }

    func refreshInfo() async throws {
        var result: [String: String] = [:]
        for (label, key) in [(String(localized: "Fabricante"), "ro.product.manufacturer"), (String(localized: "Modelo"), "ro.product.model"),
                             ("Android", "ro.build.version.release"), ("SDK", "ro.build.version.sdk")] {
            result[label] = try await shell("getprop " + key)
        }
        let memory = try await shell("cat /proc/meminfo")
        if let line = memory.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("MemAvailable:") }),
           let kb = Int64(line.split(whereSeparator: \.isWhitespace).dropFirst().first ?? "") {
            result[String(localized: "RAM disponible")] = ByteCountFormatter.string(fromByteCount: kb * 1024, countStyle: .memory)
        }
        let disk = try await shell("df -k /sdcard")
        if let line = disk.split(whereSeparator: \.isNewline).last {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.count >= 4, let total = Int64(fields[1]), let free = Int64(fields[3]) {
                result[String(localized: "Almacenamiento")] = ByteCountFormatter.string(fromByteCount: total * 1024, countStyle: .file)
                result[String(localized: "Espacio libre")] = ByteCountFormatter.string(fromByteCount: free * 1024, countStyle: .file)
            }
        }
        information = result
    }

    func packageDetails(_ package: String) async throws -> String {
        let dump = try await shell("dumpsys package " + ADBTools.quote(ADBTools.package(package)))
        let versions = dump.split(whereSeparator: \.isNewline).filter {
            $0.contains("versionName=") || $0.contains("versionCode=") || $0.contains("minSdk=")
        }.map { $0.trimmingCharacters(in: .whitespaces) }.prefix(4).joined(separator: "\n")
        let paths = try await shell("pm path " + ADBTools.quote(ADBTools.package(package)))
        var total: Int64 = 0
        for line in paths.split(whereSeparator: \.isNewline) where line.hasPrefix("package:") {
            let path = String(line.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard path.hasPrefix("/data/app/"), path.hasSuffix(".apk"), !path.contains("..") else { continue }
            let size = try await shell("du -k " + ADBTools.quote(path))
            if let first = size.split(whereSeparator: \.isWhitespace).first, let kb = Int64(first), kb >= 0, kb < 1_000_000_000 {
                total += kb * 1024
            }
        }
        return versions + (total > 0 ? "\n" + String(localized: "Tamaño: \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))") : "")
    }

    func uninstall(_ package: String) async throws {
        guard packages.contains(where: { $0.packageName == package }), package != "com.immortal.launcher" else {
            throw ADBToolError.refused(String(localized: "Esta app no se puede eliminar desde Remio para conservar el mando del Portal."))
        }
        let result = try await shell("pm uninstall " + ADBTools.quote(ADBTools.package(package)))
        guard result == "Success" else { throw ADBToolError.refused(result) }
        try await refreshPackages()
    }

    private func push(_ data: Data, to path: String) async throws {
        guard !data.isEmpty, data.count <= ADBTools.limit else { throw ADBToolError.tooLarge }
        var request = ADBTools.sync("SEND", Data((path + ",33188").utf8))
        for offset in stride(from: 0, to: data.count, by: 65536) {
            request.append(ADBTools.sync("DATA", data.subdata(in: offset..<min(offset+65536, data.count))))
        }
        request.append(ADBTools.sync("DONE", Data(), value: UInt32(Date().timeIntervalSince1970)))
        _ = try await adb.service("sync:", input: request, syncReceiving: false)
    }

    func pullAPK(_ path: String) async throws -> Data {
        guard path.hasPrefix("/data/app/"), path.hasSuffix(".apk"), !path.contains(".."), !path.contains("\0") else { throw ADBToolError.invalidData }
        return try await adb.service("sync:", input: ADBTools.sync("RECV", Data(path.utf8)), syncReceiving: true)
    }

    func install(_ data: Data) async throws {
        guard data.starts(with: [0x50, 0x4b, 0x03, 0x04]) else { throw ADBToolError.refused(String(localized: "Selecciona un archivo APK válido.")) }
        let path = "/data/local/tmp/remio-" + UUID().uuidString + ".apk"
        try await push(data, to: path)
        do {
            let output = try await shell("pm install -r " + ADBTools.quote(path))
            _ = try? await shell("rm -f " + ADBTools.quote(path))
            guard output.hasSuffix("Success") else { throw ADBToolError.refused(output) }
        } catch { _ = try? await shell("rm -f " + ADBTools.quote(path)); throw error }
    }

    func uploadPhoto(_ data: Data, extension suffix: String) async throws {
        guard ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp"].contains(suffix) else { throw ADBToolError.invalidData }
        _ = try await shell("mkdir -p /sdcard/Pictures/Remio")
        let path = "/sdcard/Pictures/Remio/" + UUID().uuidString + "." + suffix
        try await push(data, to: path)
        _ = try await shell("am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d " + ADBTools.quote("file://" + path))
    }

    func refreshUpdates() async throws {
        let all = try await shell("pm list packages")
        let disabled = try await shell("pm list packages -d")
        let installed = Set(all.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        let blocked = Set(disabled.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        otaPackages = ADBTools.updates.filter { installed.contains("package:" + $0) }
        disabledOTA = otaPackages.filter { blocked.contains("package:" + $0) }
    }

    func setUpdates(blocked: Bool) async throws {
        try await refreshUpdates()
        guard !otaPackages.isEmpty else { throw ADBToolError.refused(String(localized: "No se encontraron los componentes de actualización compatibles.")) }
        for package in otaPackages {
            _ = try await shell((blocked ? "pm disable-user --user 0 " : "pm enable --user 0 ") + ADBTools.quote(package))
        }
        try await refreshUpdates()
        guard blocked ? disabledOTA.count == otaPackages.count : disabledOTA.isEmpty else { throw ADBToolError.refused(String(localized: "No se pudo verificar el cambio.")) }
    }
    private static let settings = ["screen_brightness", "screen_off_timeout", "accelerometer_rotation", "user_rotation", "volume_music", "volume_ring", "volume_alarm"]

    func createBackup(packages selected: Set<String>) async throws -> Data {
        try await refreshPackages()
        guard !selected.isEmpty, selected.isSubset(of: Set(packages.map(\.packageName))) else { throw ADBToolError.invalidData }
        var entries: [String: Data] = [:], records: [ToolkitBackup.App] = [], settings: [String: String] = [:]
        var total = 0
        for (index, package) in selected.sorted().enumerated() {
            progress = String(localized: "Copiando app \(index+1) de \(selected.count)")
            let paths = try await shell("pm path " + ADBTools.quote(ADBTools.package(package)))
            var names: [String] = []
            for (part, line) in paths.split(whereSeparator: \.isNewline).enumerated() {
                guard line.hasPrefix("package:") else { throw ADBToolError.invalidData }
                let path = String(line.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
                let data = try await pullAPK(path)
                total += data.count
                guard total < ToolkitArchive.maxBytes else { throw ADBToolError.tooLarge }
                let name = "\(part)_app.apk"
                entries["apps/\(package)/\(name)"] = data
                names.append(name)
            }
            guard !names.isEmpty else { throw ADBToolError.invalidData }
            records.append(.init(packageName: package, files: names))
        }
        for key in Self.settings {
            let value = try await shell("settings get system " + key)
            if !value.isEmpty, value != "null", value.count < 32,
               value.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "." }) { settings["system."+key] = value }
        }
        let manufacturer = try await shell("getprop ro.product.manufacturer")
        let model = try await shell("getprop ro.product.model")
        let sdk = try await shell("getprop ro.build.version.sdk")
        let manifest = ToolkitBackup(formatVersion: 1, createdAt: Int64(Date().timeIntervalSince1970*1000),
            device: .init(manufacturer: manufacturer, model: model, sdk: sdk), settings: settings, apps: records)
        entries["manifest.json"] = try JSONEncoder().encode(manifest)
        progress = String(localized: "Preparando archivo ZIP")
        return try await Task.detached { try ToolkitArchive.encode(entries) }.value
    }

    func restoreBackup(_ entries: [String: Data], settings restoreSettings: Bool) async throws {
        let manifest = try ToolkitBackup.inspect(entries)
        let model = try await shell("getprop ro.product.model")
        let sdk = try await shell("getprop ro.build.version.sdk")
        guard manifest.device.model == model, manifest.device.sdk == sdk else {
            throw ADBToolError.refused(String(localized: "Esta copia corresponde a otro modelo o versión de Android."))
        }
        for (index, app) in manifest.apps.enumerated() {
            progress = String(localized: "Restaurando app \(index+1) de \(manifest.apps.count)")
            if app.files.count == 1 { try await install(entries["apps/\(app.packageName)/\(app.files[0])"]!) }
            else {
                let response = try await shell("pm install-create -r")
                guard let start = response.lastIndex(of: "["), let end = response.lastIndex(of: "]"), start < end,
                      let session = Int(response[response.index(after: start)..<end]), session > 0 else { throw ADBToolError.refused(response) }
                do {
                    for (part, file) in app.files.enumerated() {
                        let data = entries["apps/\(app.packageName)/\(file)"]!
                        let path = "/data/local/tmp/remio-" + UUID().uuidString + ".apk"
                        try await push(data, to: path)
                        do {
                            let reply = try await shell("pm install-write -S \(data.count) \(session) split\(part) " + ADBTools.quote(path))
                            _ = try? await shell("rm -f " + ADBTools.quote(path))
                            guard reply.hasPrefix("Success") else { throw ADBToolError.refused(reply) }
                        } catch { _ = try? await shell("rm -f " + ADBTools.quote(path)); throw error }
                    }
                    let result = try await shell("pm install-commit \(session)")
                    guard result.hasSuffix("Success") else { throw ADBToolError.refused(result) }
                } catch { _ = try? await shell("pm install-abandon \(session)"); throw error }
            }
        }
        if restoreSettings {
            for name in Self.settings {
                guard let value = manifest.settings["system." + name], !value.isEmpty, value.count < 32,
                      value.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "." }) else { continue }
                _ = try await shell("settings put system " + name + " " + ADBTools.quote(value))
            }
        }
    }

}
