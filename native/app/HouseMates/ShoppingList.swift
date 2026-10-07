import Foundation
import Observation
import Supabase

/// En ändring av listan som ännu inte nått servern.
enum PendingChange: Codable, Equatable {
    case add(id: UUID, name: String, createdAt: Date)
    case setChecked(id: UUID, checked: Bool)
    case remove(ids: [UUID])
}

/// Hushållets inköpslista. Ändringar syns direkt, sparas på telefonen och skickas i tur och ordning.
/// Utan nät (vanligt i butiken) ligger de kvar och skickas när kontakten är tillbaka. Realtid
/// hämtar om listan när partnern ändrar något.
@MainActor
@Observable
final class ShoppingList {
    private(set) var items: [ShoppingItem] = []
    private(set) var pending: [PendingChange] = []
    private(set) var isOffline = false
    var errorMessage: String?

    var open: [ShoppingItem] { items.filter { !$0.checked } }
    var bought: [ShoppingItem] { items.filter(\.checked) }

    private let client = Backend.client
    @ObservationIgnored private var fileName = ""
    @ObservationIgnored private var channel: RealtimeChannelV2?
    @ObservationIgnored private var listening: Task<Void, Never>?
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var isSending = false

    private static let retryDelay: Duration = .seconds(10)

    func start(householdID: UUID) async {
        fileName = "inkop-\(householdID.uuidString).json"
        if let saved = LocalFiles.read(SavedList.self, from: fileName) {
            items = saved.items
            pending = saved.pending
        }
        if channel == nil {
            let channel = client.channel("inkop-\(householdID.uuidString)")
            let changes = channel.postgresChange(
                AnyAction.self,
                table: "shopping_items",
                filter: .eq("household_id", value: householdID)
            )
            self.channel = channel
            listening = Task { [weak self] in
                for await _ in changes { await self?.sync() }
            }
        }
        await sync()
    }

    func stop() async {
        listening?.cancel()
        retry?.cancel()
        listening = nil
        retry = nil
        if let channel { await client.removeChannel(channel) }
        channel = nil
    }

    /// Skickar väntande ändringar och hämtar sedan listan. Utan kontakt görs ett nytt försök om en stund.
    func sync() async {
        await sendPending()
        await fetch()
        if !isOffline {
            // Ingen effekt om kanalen redan är ansluten; annars återansluts realtiden efter ett avbrott.
            try? await channel?.subscribeWithError()
        }
    }

    /// Samma vara kan inte stå på listan två gånger; att lägga till den igen gör inget.
    func add(_ rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !open.contains(where: { $0.name.lowercased() == name.lowercased() }) else { return }
        record(.add(id: UUID(), name: name, createdAt: .now))
    }

    func toggle(_ item: ShoppingItem) {
        record(.setChecked(id: item.id, checked: !item.checked))
    }

    func remove(_ item: ShoppingItem) {
        record(.remove(ids: [item.id]))
    }

    func clearBought() {
        let ids = bought.map(\.id)
        guard !ids.isEmpty else { return }
        record(.remove(ids: ids))
    }

    /// Lägger väntande ändringar ovanpå en lista, så att det man gjort utan nät syns även efter en omhämtning.
    nonisolated static func applying(_ changes: [PendingChange], to items: [ShoppingItem]) -> [ShoppingItem] {
        var result = items
        for change in changes {
            switch change {
            case let .add(id, name, createdAt):
                if !result.contains(where: { $0.id == id }) {
                    result.append(ShoppingItem(id: id, name: name, checked: false, createdAt: createdAt))
                }
            case let .setChecked(id, checked):
                if let index = result.firstIndex(where: { $0.id == id }) {
                    result[index].checked = checked
                }
            case let .remove(ids):
                result.removeAll { ids.contains($0.id) }
            }
        }
        return result
    }

    private func record(_ change: PendingChange) {
        pending.append(change)
        items = Self.applying([change], to: items)
        save()
        Task { await sendPending() }
    }

    private func sendPending() async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        while let change = pending.first {
            do {
                try await send(change)
                isOffline = false
            } catch is URLError {
                isOffline = true
                scheduleRetry()
                return
            } catch {
                // Servern nekade (t.ex. varan fanns redan); ett nytt försök skulle nekas igen, så ändringen släpps.
                if (error as? PostgrestError)?.code != "23505" { errorMessage = userMessage(for: error) }
            }
            pending.removeFirst()
            save()
        }
    }

    private func send(_ change: PendingChange) async throws {
        let table = client.from("shopping_items")
        switch change {
        case let .add(id, name, _):
            try await table.insert(NewItem(id: id, name: name)).execute()
        case let .setChecked(id, checked):
            try await table.update(["checked": checked]).eq("id", value: id).execute()
        case let .remove(ids):
            try await table.update(["deleted_at": Date.now]).in("id", values: ids).execute()
        }
    }

    private func fetch() async {
        do {
            let fresh: [ShoppingItem] = try await client.from("shopping_items")
                .select("id, name, checked, created_at")
                .is("deleted_at", value: nil)
                .order("created_at")
                .execute()
                .value
            items = Self.applying(pending, to: fresh)
            isOffline = false
            save()
        } catch is URLError {
            isOffline = true
            scheduleRetry()
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    private func scheduleRetry() {
        guard retry == nil else { return }
        retry = Task { [weak self] in
            try? await Task.sleep(for: Self.retryDelay)
            guard !Task.isCancelled else { return }
            self?.retry = nil
            await self?.sync()
        }
    }

    private func save() {
        guard !fileName.isEmpty else { return }
        LocalFiles.write(SavedList(items: items, pending: pending), to: fileName)
    }
}

private struct SavedList: Codable {
    let items: [ShoppingItem]
    let pending: [PendingChange]
}

private struct NewItem: Encodable {
    let id: UUID
    let name: String
}
