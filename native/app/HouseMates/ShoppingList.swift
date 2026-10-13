import Foundation
import Supabase

/// Hushållets inköpslista; kön och synken finns i `SyncedTable`.
typealias ShoppingList = SyncedTable<ShoppingChange>

enum ShoppingChange: TableChange {
    case add(id: UUID, name: String, qty: String?, by: UUID?, createdAt: Date)
    case setChecked(id: UUID, checked: Bool, by: UUID?)
    case remove(ids: [UUID])
    /// Ångra en borttagning.
    case restore([ShoppingItem])

    static let table = "shopping_items"
    static let columns = "id, name, qty, checked, checked_by, created_by, created_at"

    func apply(to items: inout [ShoppingItem]) {
        switch self {
        case let .add(id, name, qty, by, createdAt):
            if !items.contains(where: { $0.id == id }) {
                items.append(ShoppingItem(id: id, name: name, qty: qty, checked: false, checkedBy: nil, createdBy: by, createdAt: createdAt))
            }
        case let .setChecked(id, checked, by):
            if let index = items.firstIndex(where: { $0.id == id }) {
                items[index].checked = checked
                items[index].checkedBy = checked ? by : nil
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
        case let .add(id, name, qty, _, _):
            try await table.insert(NewItem(id: id, name: name, qty: qty)).execute()
        case let .setChecked(id, checked, _):
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
    func add(_ rawName: String, qty rawQty: String? = nil, by me: UUID?) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let qty = rawQty?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isOnList(name) else { return false }
        // Databasen tar namn på högst 80 tecken och mängder på högst 40.
        record(.add(
            id: UUID(), name: String(name.prefix(80)), qty: qty.flatMap { $0.isEmpty ? nil : String($0.prefix(40)) },
            by: me, createdAt: .now
        ))
        return true
    }

    /// Lägger en rätts ingredienser på listan som vara och mängd. Svarar med hur många som lades till.
    @discardableResult
    func add(ingredients lines: [String], by me: UUID?) -> Int {
        var added = 0
        for line in lines {
            let ingredient = Ingredient(line: line)
            if add(ingredient.name, qty: ingredient.qty, by: me) { added += 1 }
        }
        return added
    }

    /// Tidigare varor som börjar på `prefix`, de vanligaste först (`suggest_shopping`). Inga utan nät.
    func suggestions(startingWith prefix: String) async -> [String] {
        let suggestions: [Suggestion]? = try? await Backend.client
            .rpc("suggest_shopping", params: ["q": prefix])
            .execute()
            .value
        return suggestions?.map(\.name) ?? []
    }

    /// Om varan redan står obockad på listan.
    func isOnList(_ name: String) -> Bool {
        open.contains { $0.name.lowercased() == name.lowercased() }
    }

    func toggle(_ item: ShoppingItem, by me: UUID?) {
        record(.setChecked(id: item.id, checked: !item.checked, by: me))
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

private struct Suggestion: Decodable {
    let name: String
}
