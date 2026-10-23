import Foundation

/// Only literal private IPv4 addresses. Bonjour resolves to one before selection.
/// No DNS names, redirects, user info, fragments, public hosts or arbitrary paths.
struct PortalEndpoint: Codable, Hashable, Sendable, Identifiable {
    let host: String
    let port: Int
    var id: String { "\(host):\(port)" }
    var baseURL: URL { URL(string: "http://\(host):\(port)")! }

    init(host: String, port: Int = 8723) throws {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { Int($0) }
        guard parts.count == 4, octets.count == 4,
              zip(parts, octets).allSatisfy({ String($0.1) == $0.0 && (0...255).contains($0.1) }),
              octets[0] == 10 || (octets[0] == 172 && (16...31).contains(octets[1])) || (octets[0] == 192 && octets[1] == 168),
              (1...65535).contains(port) else { throw PortalError.invalidAddress }
        self.host = host
        self.port = port
    }

    init(address: String) throws {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URLComponents(string: text.contains("://") ? text : "http://\(text)"),
              url.scheme == "http", url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              ["", "/", "/remote/ui"].contains(url.path), let host = url.host else { throw PortalError.invalidAddress }
        try self.init(host: host, port: url.port ?? 8723)
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(host: values.decode(String.self, forKey: .host), port: values.decode(Int.self, forKey: .port))
    }
}

enum PortalError: Error, LocalizedError, Equatable {
    case invalidAddress, invalidPIN, unauthorized, inaccessible, incompatible
    case unavailableInput, noFocusedField, notDispatched, oversizedResponse, busy, keychain
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .invalidAddress: String(localized: "Usa una dirección IP de tu red local y el puerto del mando.")
        case .invalidPIN: String(localized: "Introduce los seis números del PIN de Immortal.")
        case .unauthorized: String(localized: "Necesitas vincular Remio con el PIN actual del Portal.")
        case .inaccessible: String(localized: "No se puede conectar. Comprueba que ambos equipos estén en la misma Wi-Fi.")
        case .incompatible: String(localized: "La respuesta del Portal no es compatible con este mando.")
        case .unavailableInput: String(localized: "Immortal no tiene disponible el control táctil. No se han cambiado permisos.")
        case .noFocusedField: String(localized: "Primero selecciona un campo de texto en el Portal.")
        case .notDispatched: String(localized: "El Portal recibió la petición pero no pudo ejecutar la acción.")
        case .oversizedResponse: String(localized: "El Portal devolvió una respuesta demasiado grande.")
        case .busy: String(localized: "Espera a que termine la acción anterior.")
        case .keychain: String(localized: "No se pudo acceder a la vinculación guardada en el llavero del iPhone.")
        case .server(let code): String(localized: "El Portal no pudo atender la petición (\(code)).")
        }
    }
}
