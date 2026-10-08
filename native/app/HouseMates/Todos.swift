import Foundation
import Supabase

struct Todo: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var assignee: UUID?          // nil = gemensamt
    var startDate: String?       // period: "gör inom start–sista dag"
    var dueDate: String?
    var done: Bool
    var doneAt: Date?
    var doneBy: UUID?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, assignee, done
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
    case update(id: UUID, title: String, assignee: UUID?, startDate: String?, dueDate: String?)
    case setDone(id: UUID, done: Bool, by: UUID?)
    case remove(ids: [UUID])

    static let table = "todos"
    static let columns = "id, title, assignee, start_date, due_date, done, done_at, done_by, created_at"

    func apply(to todos: inout [Todo]) {
        switch self {
        case let .add(todo):
            if !todos.contains(where: { $0.id == todo.id }) { todos.append(todo) }
        case let .update(id, title, assignee, startDate, dueDate):
            guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
            todos[index].title = title
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
        }
    }

    func send(to table: PostgrestQueryBuilder) async throws {
        switch self {
        case let .add(todo):
            try await table.insert(
                TodoFields(id: todo.id, title: todo.title, assignee: todo.assignee, startDate: todo.startDate, dueDate: todo.dueDate)
            ).execute()
        case let .update(id, title, assignee, startDate, dueDate):
            try await table.update(
                TodoFields(id: nil, title: title, assignee: assignee, startDate: startDate, dueDate: dueDate)
            ).eq("id", value: id).execute()
        case let .setDone(id, done, _):
            try await table.update(["done": done]).eq("id", value: id).execute()
        case let .remove(ids):
            try await table.update(["deleted_at": Date.now]).in("id", values: ids).execute()
        }
    }

    /// Tomma fält skickas som null, så att ett borttaget datum också försvinner på servern.
    private struct TodoFields: Encodable {
        let id: UUID?
        let title: String
        let assignee: UUID?
        let startDate: String?
        let dueDate: String?

        enum CodingKeys: String, CodingKey {
            case id, title, assignee
            case startDate = "start_date"
            case dueDate = "due_date"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(title, forKey: .title)
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

    func add(title: String, assignee: UUID?, startDate: String?, dueDate: String?) {
        let todo = Todo(
            id: UUID(), title: Self.limited(title), assignee: assignee, startDate: startDate, dueDate: dueDate,
            done: false, doneAt: nil, doneBy: nil, createdAt: .now
        )
        record(.add(todo))
    }

    func update(_ todo: Todo, title: String, assignee: UUID?, startDate: String?, dueDate: String?) {
        record(.update(id: todo.id, title: Self.limited(title), assignee: assignee, startDate: startDate, dueDate: dueDate))
    }

    func toggle(_ todo: Todo, by me: UUID?) {
        record(.setDone(id: todo.id, done: !todo.done, by: me))
    }

    func remove(_ todo: Todo) {
        record(.remove(ids: [todo.id]))
    }

    /// I omgångar om 50, eftersom raderna skickas i adressen till servern.
    func clearFinished() {
        for ids in finished.map(\.id).chunked(into: 50) {
            record(.remove(ids: ids))
        }
    }
}
