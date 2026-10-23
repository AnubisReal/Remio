import Foundation

/// Compile alongside PortalEndpoint.swift and PortalAPI.swift. One unauthenticated GET only.
@main
struct PortalReadProbe {
    static func main() async throws {
        guard let address = CommandLine.arguments.dropFirst().first else {
            print("Uso: PortalReadProbe IP:PUERTO")
            return
        }
        let endpoint = try PortalEndpoint(address: address)
        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent("remote/devices"))
        request.httpMethod = "GET"
        let (data, status) = try await HTTPPortalTransport().send(request)
        let result = try JSONDecoder().decode(PortalReply.self, from: data)
        guard status == 401, !result.ok, result.error == "unauthorized" else { throw PortalError.incompatible }
        print("PASS: unauthenticated read rejected with HTTP 401. No control or pairing sent.")
    }
}
