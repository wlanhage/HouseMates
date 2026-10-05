import Foundation
import Observation
import Supabase

/// Hushållets inköpslista. Ändringar visas direkt och skickas sedan; realtid hämtar om listan
/// när någon (oftast partnern) ändrar något, så listan alltid speglar databasen.
@MainActor
@Observable
final class ShoppingList {
    private(set) var items: [ShoppingItem] = []
    var errorMessage: String?

    private let client = Backend.client
    private var channel: RealtimeChannelV2?
    private var listening: Task<Void, Never>?

    var open: [ShoppingItem] { items.filter { !$0.checked } }
    var bought: [ShoppingItem] { items.filter(\.checked) }

    func start(householdID: UUID) async {
        await load()
        guard channel == nil else { return }
        let channel = client.channel("inkop-\(householdID.uuidString)")
        let changes = channel.postgresChange(
            AnyAction.self,
            table: "shopping_items",
            filter: .eq("household_id", value: householdID)
        )
        self.channel = channel
        listening = Task { [weak self] in
            for await _ in changes { await self?.load() }
        }
        do {
            try await channel.subscribeWithError()
        } catch {
            errorMessage = "Listan uppdateras inte automatiskt just nu. Dra nedåt för att hämta om."
        }
    }

    func stop() async {
        listening?.cancel()
        listening = nil
        if let channel { await client.removeChannel(channel) }
        channel = nil
    }

    func load() async {
        do {
            items = try await client.from("shopping_items")
                .select("id, name, checked, created_at")
                .is("deleted_at", value: nil)
                .order("created_at")
                .execute()
                .value
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    /// Samma vara kan inte stå på listan två gånger (unikt index); att lägga till den igen gör inget.
    func add(_ rawName: String) async {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !open.contains(where: { $0.name.lowercased() == name.lowercased() }) else { return }
        let item = ShoppingItem(id: UUID(), name: name, checked: false, createdAt: .now)
        items.append(item)
        do {
            try await client.from("shopping_items").insert(NewItem(id: item.id, name: name)).execute()
        } catch {
            // 23505: partnern la till samma vara precis innan – omhämtningen visar deras.
            if (error as? PostgrestError)?.code != "23505" { errorMessage = userMessage(for: error) }
            await load()
        }
    }

    func toggle(_ item: ShoppingItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].checked.toggle()
        await send { try client.from("shopping_items").update(["checked": !item.checked]).eq("id", value: item.id) }
    }

    func remove(_ item: ShoppingItem) async {
        items.removeAll { $0.id == item.id }
        await send { try client.from("shopping_items").update(["deleted_at": Date.now]).eq("id", value: item.id) }
    }

    func clearBought() async {
        let ids = bought.map(\.id)
        guard !ids.isEmpty else { return }
        items.removeAll(where: \.checked)
        await send { try client.from("shopping_items").update(["deleted_at": Date.now]).in("id", values: ids) }
    }

    private func send(_ request: () throws -> PostgrestFilterBuilder) async {
        do {
            try await request().execute()
        } catch {
            errorMessage = userMessage(for: error)
            await load()
        }
    }
}

private struct NewItem: Encodable {
    let id: UUID
    let name: String
}
