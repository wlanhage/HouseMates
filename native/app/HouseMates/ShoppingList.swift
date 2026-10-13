import Foundation
import Supabase

/// Hushållets inköpslista; kön och synken finns i `SyncedTable`.
typealias ShoppingList = SyncedTable<ShoppingChange>

enum ShoppingChange: TableChange {
    case add(id: UUID, name: String, qty: String?, createdAt: Date)
    case setChecked(id: UUID, checked: Bool)
    case remove(ids: [UUID])
    /// Ångra en borttagning.
    case restore([ShoppingItem])

    static let table = "shopping_items"
    static let columns = "id, name, qty, checked, created_at"

    func apply(to items: inout [ShoppingItem]) {
        switch self {
        case let .add(id, name, qty, createdAt):
            if !items.contains(where: { $0.id == id }) {
                items.append(ShoppingItem(id: id, name: name, qty: qty, checked: false, createdAt: createdAt))
            }
        case let .setChecked(id, checked):
            if let index = items.firstIndex(where: { $0.id == id }) {
                items[index].checked = checked
            }
        case let .remove(ids):
            items.removeAll { ids.contains($0.id) }
        case let .restore(restored):
            for item in restored where !items.contains(where: { $0.id == item.id }) {
                items.append(item)
            }
        }
    }

    func send(to table: PostgrestQueryBuilder) async throws {
        switch self {
        case let .add(id, name, qty, _):
            try await table.insert(NewItem(id: id, name: name, qty: qty)).execute()
        case let .setChecked(id, checked):
            try await table.update(["checked": checked]).eq("id", value: id).execute()
        case let .remove(ids):
            try await table.update(["deleted_at": Date.now]).in("id", values: ids).execute()
        case let .restore(items):
            try await table.update(Undeleted()).in("id", values: items.map(\.id)).execute()
        }
    }

    private struct NewItem: Encodable {
        let id: UUID
        let name: String
        let qty: String?
    }
}

extension SyncedTable where Change == ShoppingChange {
    var open: [ShoppingItem] { records.filter { !$0.checked } }
    var bought: [ShoppingItem] { records.filter(\.checked) }

    /// Samma vara kan inte stå på listan två gånger; att lägga till den igen gör inget.
    /// Svarar med om varan lades till.
    @discardableResult
    func add(_ rawName: String, qty: String? = nil) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isOnList(name) else { return false }
        // Databasen tar namn på högst 80 tecken och mängder på högst 40.
        record(.add(id: UUID(), name: String(name.prefix(80)), qty: qty.map { String($0.prefix(40)) }, createdAt: .now))
        return true
    }

    /// Lägger en rätts ingredienser på listan som vara och mängd. Svarar med hur många som lades till.
    @discardableResult
    func add(ingredients lines: [String]) -> Int {
        var added = 0
        for line in lines {
            let ingredient = Ingredient(line: line)
            if add(ingredient.name, qty: ingredient.qty) { added += 1 }
        }
        return added
    }

    /// Om varan redan står obockad på listan.
    func isOnList(_ name: String) -> Bool {
        open.contains { $0.name.lowercased() == name.lowercased() }
    }

    func toggle(_ item: ShoppingItem) {
        record(.setChecked(id: item.id, checked: !item.checked))
    }

    func remove(_ items: [ShoppingItem]) {
        guard let first = items.first else { return }
        removeInParts(items)
        offerUndo(items.count == 1 ? "Tog bort \(first.name)" : "Tog bort \(itemCountLabel(items.count))",
                  by: items.chunked(into: 50).map { .restore($0) })
    }

    func clearBought() {
        let items = bought
        guard !items.isEmpty else { return }
        removeInParts(items)
        offerUndo("Rensade \(itemCountLabel(items.count))", by: items.chunked(into: 50).map { .restore($0) })
    }

    /// I omgångar om 50, eftersom raderna skickas i adressen till servern.
    private func removeInParts(_ items: [ShoppingItem]) {
        for part in items.chunked(into: 50) {
            record(.remove(ids: part.map(\.id)))
        }
    }
}
