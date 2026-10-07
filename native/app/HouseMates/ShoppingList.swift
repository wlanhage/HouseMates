import Foundation
import Supabase

/// Hushållets inköpslista; kön och synken finns i `SyncedTable`.
typealias ShoppingList = SyncedTable<ShoppingChange>

enum ShoppingChange: TableChange {
    case add(id: UUID, name: String, createdAt: Date)
    case setChecked(id: UUID, checked: Bool)
    case remove(ids: [UUID])

    static let table = "shopping_items"
    static let columns = "id, name, checked, created_at"

    func apply(to items: inout [ShoppingItem]) {
        switch self {
        case let .add(id, name, createdAt):
            if !items.contains(where: { $0.id == id }) {
                items.append(ShoppingItem(id: id, name: name, checked: false, createdAt: createdAt))
            }
        case let .setChecked(id, checked):
            if let index = items.firstIndex(where: { $0.id == id }) {
                items[index].checked = checked
            }
        case let .remove(ids):
            items.removeAll { ids.contains($0.id) }
        }
    }

    func send(to table: PostgrestQueryBuilder) async throws {
        switch self {
        case let .add(id, name, _):
            try await table.insert(NewItem(id: id, name: name)).execute()
        case let .setChecked(id, checked):
            try await table.update(["checked": checked]).eq("id", value: id).execute()
        case let .remove(ids):
            try await table.update(["deleted_at": Date.now]).in("id", values: ids).execute()
        }
    }

    private struct NewItem: Encodable {
        let id: UUID
        let name: String
    }
}

extension SyncedTable where Change == ShoppingChange {
    var open: [ShoppingItem] { records.filter { !$0.checked } }
    var bought: [ShoppingItem] { records.filter(\.checked) }

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
}
