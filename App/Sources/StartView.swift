import PokerCore
import PokerNet
import PokerSession
import SwiftUI

struct StartView: View {
    let onSession: (TableSession) -> Void
    @AppStorage("playerName") private var playerName = ""
    @State private var nearby = NearbyTables()
    @State private var savedGame: HostSnapshot?
    @State private var ticket: SeatTicket?
    @State private var creating = false
    @State private var joining: DiscoveredTable?
    @State private var confirmDiscard = false
    @State private var failed = false
    @State private var deleteFailed = false
    @State private var busy = false
    @State private var showSettings = false

    private var name: String { playerName.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// "<name>'s table", with the name shortened so it fits the 63-byte Bonjour service name.
    private var defaultTableName: String {
        var short = name
        while "\(short)'s table".utf8.count > 63 { short.removeLast() }
        return "\(short)'s table"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your name") { TextField("Name", text: $playerName) }
                Section {
                    if let savedGame {
                        Button { host(savedGame) } label: {
                            VStack(alignment: .leading) {
                                Text("Resume game")
                                Text(savedGame.tableName).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Button("Discard", role: .destructive) { discard(SaveFile.host) }
                    }
                    if let ticket {
                        Button("Rejoin \(ticket.tableName)") { rejoin(ticket) }
                        Button("Discard", role: .destructive) { discard(SaveFile.seat) }
                    }
                    Button("Create table") { if savedGame == nil { creating = true } else { confirmDiscard = true } }
                }
                .disabled(name.isEmpty || busy)
                if busy { ProgressView().frame(maxWidth: .infinity) }
                Section("Nearby tables") {
                    if nearby.localNetworkDenied { LocalNetworkNotice() }
                    if nearby.tables.isEmpty { Text("Looking for tables…").foregroundStyle(.secondary) }
                    ForEach(nearby.tables, id: \.self) { table in
                        Button(table.name) { joining = table }.disabled(name.isEmpty || busy)
                    }
                }
            }
            .navigationTitle("PokerChipCase")
            .toolbar { Button("Settings", systemImage: "gearshape") { showSettings = true } }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .task { await nearby.run() }
        #if DEBUG
        .task { if DebugBots.auto, !name.isEmpty { host(.newTable(hostName: name, tableName: defaultTableName, config: .quick)) } }
        #endif
        .onAppear(perform: reload)
        .sheet(isPresented: $creating) {
            CreateTableSheet(defaultName: defaultTableName, busy: busy) { tableName, config in
                host(.newTable(hostName: name, tableName: tableName, config: config))
            }
        }
        .sheet(item: $joining) { table in
            JoinSheet(table: table) { code in
                let name = name
                // Same table as the stored ticket: rejoin its seat instead of taking a new one.
                let token = ticket.flatMap { $0.tableName == table.name && $0.code == code ? $0.token : nil }
                // The endpoint listed now: it may have changed while the sheet was open.
                let endpoint = nearby.tables.first { $0.name == table.name }?.endpoint ?? table.endpoint
                connect {
                    await TableSession.join(endpoint: endpoint, tableName: table.name, code: code, name: name,
                                            token: token)
                }
            }
        }
        .confirmationDialog("Discard the saved game?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard and create", role: .destructive) { creating = true }
        }
        .alert("Could not open the table", isPresented: $failed) {
            // No actions: the system adds an OK button.
        }
        .alert("Could not delete the saved game", isPresented: $deleteFailed) {
            // No actions: the system adds an OK button.
        }
    }

    private func discard<V>(_ file: SaveFile<V>) {
        do { try file.delete() } catch { deleteFailed = true }
        reload()
    }

    private func reload() {
        savedGame = SaveFile.host.load().flatMap { $0.isResumable ? $0 : nil }
        ticket = SaveFile.seat.load()
    }

    private func host(_ snapshot: HostSnapshot) {
        connect {
            do { return try await TableSession.host(snapshot) } catch { failed = true; return nil }
        }
    }

    private func rejoin(_ ticket: SeatTicket) {
        connect {
            await TableSession.join(
                endpoint: ticket.endpoint, tableName: ticket.tableName, code: ticket.code, name: ticket.name,
                token: ticket.token)
        }
    }

    /// One connection attempt at a time; `busy` disables every action meanwhile.
    private func connect(_ open: @escaping () async -> TableSession?) {
        guard !busy else { return }
        busy = true
        Task {
            let session = await open()
            busy = false
            if let session { onSession(session) }
        }
    }
}

extension DiscoveredTable: @retroactive Identifiable { public var id: Self { self } }

private struct CreateTableSheet: View {
    let defaultName: String
    let busy: Bool
    let onCreate: (String, TournamentConfig) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tableName = ""
    @State private var preset = 0

    private var finalName: String {
        let trimmed = tableName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultName : trimmed
    }
    /// Bonjour service names are limited to 63 UTF-8 bytes.
    private var tooLong: Bool { finalName.utf8.count > 63 }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Table name", text: $tableName)
                if tooLong { Text("Name is too long").foregroundStyle(.red) }
                Picker("Blinds", selection: $preset) {
                    ForEach(TournamentConfig.presets.indices, id: \.self) { Text(TournamentConfig.presets[$0].name).tag($0) }
                }
            }
            .navigationTitle("Create table")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        dismiss()
                        onCreate(finalName, TournamentConfig.presets[preset].config)
                    }
                    .disabled(busy || tooLong)
                }
            }
            .onAppear { tableName = defaultName }
        }
    }
}

private struct JoinSheet: View {
    let table: DiscoveredTable
    let onJoin: (TableCode) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            // Focused on open, so the number pad is up and the code can be typed right away.
            Form { TextField("Code", text: $text).keyboardType(.numberPad).focused($codeFocused) }
                .onAppear { codeFocused = true }
                .navigationTitle(table.name)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Join") {
                            guard let code = TableCode(text) else { return }
                            dismiss()
                            onJoin(code)
                        }
                        .disabled(TableCode(text) == nil)
                    }
                }
        }
    }
}
