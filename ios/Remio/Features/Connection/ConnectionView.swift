import SwiftUI

struct ConnectionView: View {
    @Environment(RemoteModel.self) private var remote
    @Environment(AdministrationModel.self) private var administration
    @Environment(\.dismiss) private var dismiss
    @State private var discovery = PortalDiscovery()
    @State private var adbDiscovery = ADBDiscovery()
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
                    TextField(String(localized: "Dirección IP"), text: $address)
                        .focused($focusedField, equals: .address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .disabled(remote.isPairing || administration.isChecking)
                }
                Section(String(localized: "Mando")) {
                    LabeledContent(String(localized: "Puerto")) {
                        TextField("8723", text: $remotePort)
                            .focused($focusedField, equals: .remotePort)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .disabled(remote.isPairing || administration.isChecking)
                    }
                    LabeledContent(String(localized: "Conexión"), value: selectedEndpoint == remote.endpoint ? remote.status : String(localized: "Sin vincular"))
                    if showPairing || remote.needsPairing || selectedEndpoint != remote.endpoint {
                        SecureField(String(localized: "PIN de seis cifras"), text: $pin)
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
                            HStack { Text(String(localized: "Vincular mando")); Spacer(); if remote.isPairing { ProgressView() } }
                        }
                        .disabled(pin.count != 6 || remote.isPairing || selectedEndpoint == nil)
                    } else {
                        if !remote.isConnected {
                            Button(String(localized: "Reconectar mando")) { Task { await remote.refresh() } }
                        }
                        Button(String(localized: "Volver a vincular")) { showPairing = true; focusedField = .pin }
                    }
                }
                Section {
                    LabeledContent(String(localized: "Puerto")) {
                        TextField("5555", text: $adbPort)
                            .focused($focusedField, equals: .adbPort)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .disabled(administration.isChecking)
                    }
                    if let endpoint = selectedEndpoint {
                        LabeledContent(String(localized: "Dirección"), value: "\(endpoint.host):\(adbPort)")
                            .font(.subheadline)
                    }
                    if administration.checkedAddress == selectedEndpoint.map({ "\($0.host):\(adbPort)" }) {
                        Text(administration.status).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button {
                        guard let endpoint = selectedEndpoint else { return }
                        administration.check(host: endpoint.host, port: adbPort)
                    } label: {
                        HStack { Text(administration.isConnected ? String(localized: "Reconectar ADB") : String(localized: "Conectar ADB")); Spacer(); if administration.isChecking { ProgressView() } }
                    }.disabled(selectedEndpoint == nil || administration.isChecking || remote.isPairing)
                } header: { Text(String(localized: "Administración · ADB")) } footer: { Text(String(localized: "Acepta la autorización de Remio en el Portal la primera vez.")) }
                Section {
                    Button {
                        focusedField = nil
                        adbDiscovery.start(port: Int(adbPort) ?? 0, excluding: administration.isConnected ? administration.savedEndpoint : nil)
                    } label: { Label(String(localized: "Buscar servicios ADB"), systemImage: "wifi") }
                        .disabled(adbDiscovery.running || administration.isChecking || administration.isBusy || remote.isPairing)
                    if adbDiscovery.running {
                        ProgressView(value: Double(adbDiscovery.completed), total: Double(max(1, adbDiscovery.total)))
                        Button(String(localized: "Cancelar"), role: .cancel) { adbDiscovery.stop() }
                    }
                    ForEach(adbDiscovery.hosts, id: \.self) { host in
                        Button {
                            address = host
                            administration.check(host: host, port: adbPort)
                        } label: {
                            HStack { Text(host); Spacer(); Image(systemName: "chevron.right").font(.caption) }
                        }.disabled(adbDiscovery.running || administration.isChecking || administration.isBusy || remote.isPairing)
                    }
                    if let message = adbDiscovery.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text(String(localized: "Búsqueda ADB")) } footer: {
                    Text(String(localized: "Busca hasta 253 direcciones de tu segmento Wi-Fi. Los resultados son servicios ADB sin identificar; selecciona uno para autorizar y comprobar el equipo."))
                }
                if let message = remote.message {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { focusedField = nil }
            .tint(RemioTheme.accent)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationTitle(String(localized: "Conectar Portal")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Cerrar"), systemImage: "xmark") { dismiss() }.disabled(remote.isPairing)
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
            .onDisappear { discovery.stop(); adbDiscovery.stop(); pin = "" }
        }
    }
}
