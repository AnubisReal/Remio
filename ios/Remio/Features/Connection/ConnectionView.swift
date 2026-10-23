import SwiftUI

struct ConnectionView: View {
    @Environment(RemoteModel.self) private var remote
    @Environment(AdministrationModel.self) private var administration
    @Environment(\.dismiss) private var dismiss
    @State private var discovery = PortalDiscovery()
    @State private var address = ""
    @State private var pin = ""
    @State private var showPairing = false
    @State private var adbPort = "5555"
    @FocusState private var pinFocused: Bool

    private var selectedEndpoint: PortalEndpoint? { try? PortalEndpoint(address: address) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Portal") {
                    ForEach(discovery.devices) { device in
                        Button {
                            address = device.endpoint.id
                            showPairing = remote.endpoint != device.endpoint || remote.needsPairing
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "display")
                                Text(device.name).foregroundStyle(.primary)
                                Spacer()
                                if address == device.endpoint.id { Image(systemName: "checkmark") }
                            }
                        }.disabled(remote.isPairing || administration.isChecking)
                    }
                    if discovery.devices.isEmpty {
                        Text(discovery.status).font(.footnote).foregroundStyle(.secondary)
                    }
                    TextField("IP y puerto del mando", text: $address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .disabled(remote.isPairing || administration.isChecking)
                }
                Section("Mando") {
                    LabeledContent("Conexión", value: selectedEndpoint == remote.endpoint ? remote.status : "Sin vincular")
                    if showPairing || remote.needsPairing || selectedEndpoint != remote.endpoint {
                        SecureField("PIN de seis cifras", text: $pin)
                            .keyboardType(.numberPad).textContentType(.oneTimeCode)
                            .focused($pinFocused).disabled(remote.isPairing)
                            .onChange(of: pin) { _, value in pin = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6)) }
                        Button {
                            pinFocused = false
                            let submitted = pin
                            pin = ""
                            Task {
                                await remote.pair(address: address, pin: submitted)
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
                        Button("Volver a vincular") { showPairing = true; pinFocused = true }
                    }
                }
                Section {
                    LabeledContent("Puerto") {
                        TextField("5555", text: $adbPort)
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
            .tint(RemioTheme.accent)
            .navigationTitle("Conectar Portal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar", systemImage: "xmark") { dismiss() }.disabled(remote.isPairing)
                }
            }
            .interactiveDismissDisabled(remote.isPairing)
            .onAppear {
                address = remote.endpoint?.id ?? address
                adbPort = String(administration.savedEndpoint?.port ?? 5555)
                remote.message = nil
                discovery.start()
            }
            .onDisappear { discovery.stop(); pin = "" }
        }
    }
}
