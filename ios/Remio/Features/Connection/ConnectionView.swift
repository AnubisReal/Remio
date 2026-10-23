import SwiftUI

struct ConnectionView: View {
    @Environment(RemoteModel.self) private var remote
    @Environment(AdministrationModel.self) private var administration
    @Environment(\.dismiss) private var dismiss
    @State private var discovery = PortalDiscovery()
    @State private var address = ""
    @State private var pin = ""
    @State private var showPairing = false
    @State private var remotePort = "8723"
    @State private var adbPort = "5555"
    private enum Field: Hashable { case address, remotePort, adbPort, pin }
    @FocusState private var focusedField: Field?

    private var selectedEndpoint: PortalEndpoint? {
        guard let port = Int(remotePort), let parsed = try? PortalEndpoint(address: address) else { return nil }
        return try? PortalEndpoint(host: parsed.host, port: port)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Portal") {
                    ForEach(discovery.devices) { device in
                        Button {
                            address = device.endpoint.host
                            remotePort = String(device.endpoint.port)
                            showPairing = remote.endpoint != device.endpoint || remote.needsPairing
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "display")
                                Text(device.name).foregroundStyle(.primary)
                                Spacer()
                                if selectedEndpoint == device.endpoint { Image(systemName: "checkmark") }
                            }
                        }.disabled(remote.isPairing || administration.isChecking)
                    }
                    if discovery.devices.isEmpty {
                        Text(discovery.status).font(.footnote).foregroundStyle(.secondary)
                    }
                    TextField("Dirección IP", text: $address)
                        .focused($focusedField, equals: .address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .disabled(remote.isPairing || administration.isChecking)
                }
                Section("Mando") {
                    LabeledContent("Puerto") {
                        TextField("8723", text: $remotePort)
                            .focused($focusedField, equals: .remotePort)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .disabled(remote.isPairing || administration.isChecking)
                    }
                    LabeledContent("Conexión", value: selectedEndpoint == remote.endpoint ? remote.status : "Sin vincular")
                    if showPairing || remote.needsPairing || selectedEndpoint != remote.endpoint {
                        SecureField("PIN de seis cifras", text: $pin)
                            .keyboardType(.numberPad).textContentType(.oneTimeCode)
                            .focused($focusedField, equals: .pin).disabled(remote.isPairing)
                            .onChange(of: pin) { _, value in pin = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6)) }
                        Button {
                            focusedField = nil
                            guard let endpoint = selectedEndpoint else { return }
                            let submitted = pin
                            pin = ""
                            Task {
                                await remote.pair(address: endpoint.id, pin: submitted)
                                await remote.refresh()
                            }
                        } label: {
                            HStack { Text("Vincular mando"); Spacer(); if remote.isPairing { ProgressView() } }
                        }
                        .disabled(pin.count != 6 || remote.isPairing || selectedEndpoint == nil)
                    } else {
                        if !remote.isConnected {
                            Button("Reconectar mando") { Task { await remote.refresh() } }
                        }
                        Button("Volver a vincular") { showPairing = true; focusedField = .pin }
                    }
                }
                Section {
                    LabeledContent("Puerto") {
                        TextField("5555", text: $adbPort)
                            .focused($focusedField, equals: .adbPort)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .disabled(administration.isChecking)
                    }
                    if let endpoint = selectedEndpoint {
                        LabeledContent("Dirección", value: "\(endpoint.host):\(adbPort)")
                            .font(.subheadline)
                    }
                    if administration.checkedAddress == selectedEndpoint.map({ "\($0.host):\(adbPort)" }) {
                        Text(administration.status).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button {
                        guard let endpoint = selectedEndpoint else { return }
                        administration.check(host: endpoint.host, port: adbPort)
                    } label: {
                        HStack { Text(administration.isConnected ? "Reconectar ADB" : "Conectar ADB"); Spacer(); if administration.isChecking { ProgressView() } }
                    }.disabled(selectedEndpoint == nil || administration.isChecking || remote.isPairing)
                } header: { Text("Administración · ADB") } footer: { Text("Acepta la autorización de Remio en el Portal la primera vez.") }
                if let message = remote.message {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { focusedField = nil }
            .tint(RemioTheme.accent)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationTitle("Conectar Portal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar", systemImage: "xmark") { dismiss() }.disabled(remote.isPairing)
                }
            }
            .interactiveDismissDisabled(remote.isPairing)
            .onAppear {
                address = remote.endpoint?.host ?? administration.savedEndpoint?.host ?? address
                remotePort = String(remote.endpoint?.port ?? 8723)
                adbPort = String(administration.savedEndpoint?.port ?? 5555)
                remote.message = nil
                discovery.start()
            }
            .onChange(of: address) { _, value in
                // Preserve pasting a full remote URL or IP:port while keeping the fields separate.
                if value.contains(":"), let endpoint = try? PortalEndpoint(address: value) {
                    remotePort = String(endpoint.port)
                    address = endpoint.host
                }
            }
            .onDisappear { discovery.stop(); pin = "" }
        }
    }
}
