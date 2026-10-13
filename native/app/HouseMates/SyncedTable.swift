import Foundation
import Observation
import Supabase

/// En ändring i en av hushållets tabeller: hur den syns i listan direkt, och hur den skickas.
/// Ändringarna måste gå att skicka flera gånger utan skada (klientens UUID, sätt värden,
/// mjuk radering), eftersom en ändring kan skickas igen efter ett nätfel.
protocol TableChange: Codable, Equatable, Sendable {
    associatedtype Record: Codable & Identifiable & Equatable
    static var table: String { get }
    /// Kolumnerna som hämtas till `Record`.
    static var columns: String { get }
    func apply(to records: inout [Record])
    func send(to table: PostgrestQueryBuilder) async throws
}

/// En av hushållets tabeller på telefonen. Ändringar syns direkt, sparas på telefonen och skickas
/// i tur och ordning. Utan nät (vanligt i butiken) ligger de kvar och skickas när kontakten är
/// tillbaka. Realtid hämtar om tabellen när partnern ändrar något.
@MainActor
@Observable
final class SyncedTable<Change: TableChange> {
    private(set) var records: [Change.Record] = []
    private(set) var pending: [Change] = []
    private(set) var isOffline = false
    var errorMessage: String?
    /// Det senaste som går att ångra, en kort stund (se `offerUndo`).
    private(set) var undo: UndoOffer?

    private let client = Backend.client
    private let retryDelay: Duration = .seconds(10)
    @ObservationIgnored private var fileName = ""
    @ObservationIgnored private var channel: RealtimeChannelV2?
    @ObservationIgnored private var listening: Task<Void, Never>?
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var isSending = false
    @ObservationIgnored private var isSyncing = false
    @ObservationIgnored private var needsAnotherSync = false
    @ObservationIgnored private var undoChanges: [Change] = []
    @ObservationIgnored private var undoExpiry: Task<Void, Never>?

    /// Visar direkt det som sparats på telefonen och hämtar sedan nytt i bakgrunden.
    func start(householdID: UUID) {
        fileName = "\(Change.table)-\(householdID.uuidString).json"
        if let saved = LocalFiles.read(Saved.self, from: fileName) {
            records = saved.records
            pending = saved.pending
        }
        if channel == nil {
            let channel = client.channel("\(Change.table)-\(householdID.uuidString)")
            let changes = channel.postgresChange(
                AnyAction.self,
                table: Change.table,
                filter: .eq("household_id", value: householdID)
            )
            self.channel = channel
            listening = Task { [weak self] in
                for await _ in changes { self?.syncInBackground() }
            }
        }
        syncInBackground()
    }

    /// Efter utloggning eller att man lämnat hushållet: inget mer skickas eller sparas på telefonen.
    func stop() async {
        listening?.cancel()
        retry?.cancel()
        listening = nil
        retry = nil
        fileName = ""
        dismissUndo()
        if let channel { await client.removeChannel(channel) }
        channel = nil
    }

    /// Skickar väntande ändringar och hämtar sedan tabellen. Utan kontakt görs ett nytt försök om en stund.
    /// Pågår redan en synk görs en till efteråt i stället för samtidigt, så att flera ändringar i rad
    /// från partnern ger en hämtning och ett äldre svar aldrig skriver över ett nyare.
    func sync() async {
        guard !isSyncing else {
            needsAnotherSync = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            needsAnotherSync = false
            await sendPending()
            await fetch()
        } while needsAnotherSync
        reconnectRealtime()
    }

    private func syncInBackground() {
        Task { await sync() }
    }

    /// Realtiden återansluts för sig efter ett avbrott, så att en blockerad anslutning inte håller
    /// kvar synken (ett försök kan ta upp till en minut).
    private func reconnectRealtime() {
        guard !isOffline, let channel, channel.status == .unsubscribed else { return }
        Task { try? await channel.subscribeWithError() }
    }

    func record(_ change: Change) {
        pending.append(change)
        change.apply(to: &records)
        save()
        Task { await sendPending() }
    }

    /// Visar "Ångra" i sex sekunder, som i webbappen. Ändringarna tar tillbaka det som just gjordes
    /// och går genom kön som alla andra, så att ångra fungerar även utan nät.
    func offerUndo(_ message: String, by changes: [Change]) {
        undo = UndoOffer(message: message)
        undoChanges = changes
        undoExpiry?.cancel()
        undoExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.dismissUndo()
        }
    }

    func performUndo() {
        let changes = undoChanges
        dismissUndo()
        changes.forEach(record)
    }

    func dismissUndo() {
        undo = nil
        undoChanges = []
        undoExpiry?.cancel()
    }

    /// Lägger väntande ändringar ovanpå en lista, så att det man gjort utan nät syns även efter en omhämtning.
    nonisolated static func applying(_ changes: [Change], to records: [Change.Record]) -> [Change.Record] {
        var result = records
        for change in changes { change.apply(to: &result) }
        return result
    }

    private func sendPending() async {
        guard !isSending, !pending.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        guard await hasSession() else { return }
        while let change = pending.first {
            do {
                try await change.send(to: client.from(Change.table))
                isOffline = false
            } catch let error where Self.isRejected(error) {
                // Ett nytt försök skulle nekas igen, så ändringen släpps. En dubblett är inget fel.
                if (error as? PostgrestError)?.code != "23505" { errorMessage = Self.rejectionMessage(error) }
            } catch {
                waitForServer(after: error)
                return
            }
            pending.removeFirst()
            save()
        }
    }

    /// Utan giltig inloggning skickar SDK:n den anonyma nyckeln. Då ser databasen inga rader, och en
    /// ändring skulle räknas som skickad fast inget hände. Därför kontrolleras inloggningen först;
    /// går den inte att förnya (t.ex. dålig täckning) väntar ändringarna som vid nätfel.
    private func hasSession() async -> Bool {
        do {
            _ = try await client.auth.session
            return true
        } catch {
            waitForServer(after: error)
            return false
        }
    }

    /// Servern har sagt nej till själva ändringen, och ett nytt försök skulle nekas igen: ogiltigt
    /// värde (22), dubblett eller annan regel (23), behörighet eller fel i frågan (42), ett eget fel
    /// från en funktion (P0001), en felaktig begäran (PGRST1, 4xx utom 401, 408 och 429) eller ett
    /// svar som inte går att läsa. Allt annat, som inget nät eller en server som inte svarar, går över.
    nonisolated static func isRejected(_ error: Error) -> Bool {
        if let code = (error as? PostgrestError)?.code {
            return ["22", "23", "42"].contains(String(code.prefix(2))) || code == "P0001" || code.hasPrefix("PGRST1")
        }
        if let status = (error as? HTTPError)?.response.statusCode {
            return (400..<500).contains(status) && ![401, 408, 429].contains(status)
        }
        return error is DecodingError
    }

    private nonisolated static func rejectionMessage(_ error: Error) -> String {
        if let error = error as? PostgrestError, error.code == "P0001" { return error.message }
        return "En ändring kunde inte sparas och har tagits bort."
    }

    /// Ändringarna ligger kvar och skickas igen om en stund.
    private func waitForServer(after error: Error) {
        let wasCancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
        if !wasCancelled { isOffline = true }
        scheduleRetry()
    }

    private func fetch() async {
        guard await hasSession() else { return }
        do {
            let fresh: [Change.Record] = try await client.from(Change.table)
                .select(Change.columns)
                .is("deleted_at", value: nil)
                .order("created_at")
                .execute()
                .value
            records = Self.applying(pending, to: fresh)
            isOffline = false
            save()
        } catch let error where Self.isRejected(error) {
            errorMessage = "Listan kunde inte hämtas. Försök igen senare."
        } catch {
            waitForServer(after: error)
        }
    }

    private func scheduleRetry() {
        guard retry == nil else { return }
        retry = Task { [weak self, retryDelay] in
            try? await Task.sleep(for: retryDelay)
            guard !Task.isCancelled else { return }
            self?.retry = nil
            await self?.sync()
        }
    }

    private func save() {
        guard !fileName.isEmpty else { return }
        LocalFiles.write(Saved(records: records, pending: pending), to: fileName)
    }

    private struct Saved: Codable {
        let records: [Change.Record]
        let pending: [Change]
    }
}

/// `deleted_at = null`: tar tillbaka en mjukt raderad rad. Null skickas uttryckligen, annars
/// skulle fältet utelämnas och ingenting ändras.
struct Undeleted: Encodable {
    enum CodingKeys: String, CodingKey { case deletedAt = "deleted_at" }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNil(forKey: .deletedAt)
    }
}

extension Array {
    /// Delar upp i bitar om högst `size`, t.ex. så att en adress till servern inte blir för lång.
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
