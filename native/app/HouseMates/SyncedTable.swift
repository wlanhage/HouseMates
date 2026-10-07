import Foundation
import Observation
import Supabase

/// En ändring i en av hushållets tabeller: hur den syns i listan direkt, och hur den skickas.
/// Ändringarna måste gå att skicka flera gånger utan skada (klientens UUID, sätt värden,
/// mjuk radering), eftersom en ändring kan skickas igen efter ett nätfel.
protocol TableChange: Codable, Equatable {
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

    private let client = Backend.client
    private let retryDelay: Duration = .seconds(10)
    @ObservationIgnored private var fileName = ""
    @ObservationIgnored private var channel: RealtimeChannelV2?
    @ObservationIgnored private var listening: Task<Void, Never>?
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var isSending = false

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
                for await _ in changes { await self?.sync() }
            }
        }
        Task { await sync() }
    }

    /// Efter utloggning eller att man lämnat hushållet: inget mer skickas eller sparas på telefonen.
    func stop() async {
        listening?.cancel()
        retry?.cancel()
        listening = nil
        retry = nil
        fileName = ""
        if let channel { await client.removeChannel(channel) }
        channel = nil
    }

    /// Skickar väntande ändringar och hämtar sedan tabellen. Utan kontakt görs ett nytt försök om en stund.
    func sync() async {
        await sendPending()
        await fetch()
        if !isOffline {
            // Ingen effekt om kanalen redan är ansluten; annars återansluts realtiden efter ett avbrott.
            try? await channel?.subscribeWithError()
        }
    }

    func record(_ change: Change) {
        pending.append(change)
        change.apply(to: &records)
        save()
        Task { await sendPending() }
    }

    /// Lägger väntande ändringar ovanpå en lista, så att det man gjort utan nät syns även efter en omhämtning.
    nonisolated static func applying(_ changes: [Change], to records: [Change.Record]) -> [Change.Record] {
        var result = records
        for change in changes { change.apply(to: &result) }
        return result
    }

    private func sendPending() async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        while let change = pending.first {
            do {
                try await change.send(to: client.from(Change.table))
                isOffline = false
            } catch let error where Self.isRejected(error) {
                // Ett nytt försök skulle nekas igen, så ändringen släpps. En dubblett är inget fel.
                if (error as? PostgrestError)?.code != "23505" { errorMessage = userMessage(for: error) }
            } catch {
                waitForServer(after: error)
                return
            }
            pending.removeFirst()
            save()
        }
    }

    /// Databasen har svarat med en felkod (t.ex. dubblett eller ogiltigt värde), eller svaret går
    /// inte att läsa. Andra fel, som inget nät eller en server som inte svarar, går över.
    nonisolated static func isRejected(_ error: Error) -> Bool {
        (error as? PostgrestError)?.code != nil || error is DecodingError
    }

    /// Ändringarna ligger kvar och skickas igen om en stund.
    private func waitForServer(after error: Error) {
        if !(error is CancellationError) { isOffline = true }
        scheduleRetry()
    }

    private func fetch() async {
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
            errorMessage = userMessage(for: error)
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
