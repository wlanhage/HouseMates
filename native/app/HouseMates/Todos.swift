import Foundation
import Supabase

struct Todo: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var notes: String?
    var assignee: UUID?          // nil = gemensamt
    var startDate: String?       // period: "gör inom start–sista dag"
    var dueDate: String?
    var done: Bool
    var doneAt: Date?
    var doneBy: UUID?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, notes, assignee, done
        case startDate = "start_date"
        case dueDate = "due_date"
        case doneAt = "done_at"
        case doneBy = "done_by"
        case createdAt = "created_at"
    }
}

/// Hushållets uppgifter; kön och synken finns i `SyncedTable`.
typealias TodoList = SyncedTable<TodoChange>

enum TodoChange: TableChange {
    case add(Todo)
    case update(id: UUID, title: String, notes: String?, assignee: UUID?, startDate: String?, dueDate: String?)
    case setDone(id: UUID, done: Bool, by: UUID?)
    case remove(ids: [UUID])
    /// Ångra en borttagning.
    case restore([Todo])

    static let table = "todos"
    static let columns = "id, title, notes, assignee, start_date, due_date, done, done_at, done_by, created_at"

    func apply(to todos: inout [Todo]) {
        switch self {
        case let .add(todo):
            if !todos.contains(where: { $0.id == todo.id }) { todos.append(todo) }
        case let .update(id, title, notes, assignee, startDate, dueDate):
            guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
            todos[index].title = title
            todos[index].notes = notes
            todos[index].assignee = assignee
            todos[index].startDate = startDate
            todos[index].dueDate = dueDate
        case let .setDone(id, done, by):
            guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
            todos[index].done = done
            todos[index].doneAt = done ? (todos[index].doneAt ?? .now) : nil
            todos[index].doneBy = done ? by : nil
        case let .remove(ids):
            todos.removeAll { ids.contains($0.id) }
        case let .restore(restored):
            for todo in restored where !todos.contains(where: { $0.id == todo.id }) {
                todos.append(todo)
            }
        }
    }

    func send(to table: PostgrestQueryBuilder) async throws {
        switch self {
        case let .add(todo):
            try await table.insert(TodoFields(
                id: todo.id, title: todo.title, notes: todo.notes, assignee: todo.assignee,
                startDate: todo.startDate, dueDate: todo.dueDate
            )).execute()
        case let .update(id, title, notes, assignee, startDate, dueDate):
            try await table.update(TodoFields(
                id: nil, title: title, notes: notes, assignee: assignee, startDate: startDate, dueDate: dueDate
            )).eq("id", value: id).execute()
        case let .setDone(id, done, _):
            try await table.update(["done": done]).eq("id", value: id).execute()
        case let .remove(ids):
            try await table.update(["deleted_at": Date.now]).in("id", values: ids).execute()
        case let .restore(todos):
            try await table.update(Undeleted()).in("id", values: todos.map(\.id)).execute()
        }
    }

    /// Tomma fält skickas som null, så att ett borttaget datum också försvinner på servern.
    private struct TodoFields: Encodable {
        let id: UUID?
        let title: String
        let notes: String?
        let assignee: UUID?
        let startDate: String?
        let dueDate: String?

        enum CodingKeys: String, CodingKey {
            case id, title, notes, assignee
            case startDate = "start_date"
            case dueDate = "due_date"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(title, forKey: .title)
            try container.encode(notes, forKey: .notes)
            try container.encode(assignee, forKey: .assignee)
            try container.encode(startDate, forKey: .startDate)
            try container.encode(dueDate, forKey: .dueDate)
        }
    }
}

extension SyncedTable where Change == TodoChange {
    /// Närmast sista dag först; uppgifter utan datum sist, i den ordning de lades till.
    var open: [Todo] {
        records.filter { !$0.done }.sorted { a, b in
            switch (a.dueDate, b.dueDate) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.createdAt < b.createdAt
            }
        }
    }

    var finished: [Todo] {
        records.filter(\.done).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }

    /// Databasen tar titlar på högst 200 tecken.
    private static func limited(_ title: String) -> String { String(title.prefix(200)) }

    /// Tomma anteckningar sparas som inga; databasen tar högst 1 000 tecken.
    nonisolated static func limited(notes: String) -> String? {
        let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes.isEmpty ? nil : String(notes.prefix(1000))
    }

    func add(title: String, notes: String, assignee: UUID?, startDate: String?, dueDate: String?) {
        let todo = Todo(
            id: UUID(), title: Self.limited(title), notes: Self.limited(notes: notes), assignee: assignee,
            startDate: startDate, dueDate: dueDate, done: false, doneAt: nil, doneBy: nil, createdAt: .now
        )
        record(.add(todo))
    }

    func update(_ todo: Todo, title: String, notes: String, assignee: UUID?, startDate: String?, dueDate: String?) {
        record(.update(
            id: todo.id, title: Self.limited(title), notes: Self.limited(notes: notes), assignee: assignee,
            startDate: startDate, dueDate: dueDate
        ))
    }

    func toggle(_ todo: Todo, by me: UUID?) {
        record(.setDone(id: todo.id, done: !todo.done, by: me))
        if !todo.done {
            offerUndo("Klar: \(todo.title)", by: [.setDone(id: todo.id, done: false, by: me)])
        }
    }

    func remove(_ todos: [Todo]) {
        guard let first = todos.first else { return }
        removeInParts(todos)
        offerUndo(todos.count == 1 ? "Tog bort \(first.title)" : "Tog bort \(todos.count) uppgifter",
                  by: todos.chunked(into: 50).map { .restore($0) })
    }

    func clearFinished() {
        let todos = finished
        guard !todos.isEmpty else { return }
        removeInParts(todos)
        offerUndo(todos.count == 1 ? "Rensade 1 klar uppgift" : "Rensade \(todos.count) klara uppgifter",
                  by: todos.chunked(into: 50).map { .restore($0) })
    }

    /// I omgångar om 50, eftersom raderna skickas i adressen till servern.
    private func removeInParts(_ todos: [Todo]) {
        for part in todos.chunked(into: 50) {
            record(.remove(ids: part.map(\.id)))
        }
    }
}
