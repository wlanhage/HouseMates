import Foundation
import Supabase

/// Vem en kalenderhändelse är för. Händelsen finns bara i telefonerna; här sparas dess UID.
/// Ingen rad betyder gemensamt.
struct EventAssignee: Codable, Identifiable, Equatable {
    let id: UUID
    let eventUID: String
    var assignee: UUID?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, assignee
        case eventUID = "event_uid"
        case createdAt = "created_at"
    }
}

/// Hushållets val av "för vem" på händelser; kön och synken finns i `SyncedTable`.
typealias EventAssigneeList = SyncedTable<EventAssigneeChange>

enum EventAssigneeChange: TableChange {
    case set(EventAssignee)
    case remove(ids: [UUID])

    static let table = "event_assignees"
    static let columns = "id, event_uid, assignee, created_at"

    func apply(to rows: inout [EventAssignee]) {
        switch self {
        case let .set(row):
            if let index = rows.firstIndex(where: { $0.id == row.id }) {
                rows[index] = row
            } else {
                rows.append(row)
            }
        case let .remove(ids):
            rows.removeAll { ids.contains($0.id) }
        }
    }

    func send(to table: PostgrestQueryBuilder) async throws {
        switch self {
        case let .set(row):
            try await table.upsert(Row(id: row.id, eventUID: row.eventUID, assignee: row.assignee)).execute()
        case let .remove(ids):
            try await table.update(["deleted_at": Date.now]).in("id", values: ids).execute()
        }
    }

    /// Personen skickas som null när händelsen blir gemensam igen.
    private struct Row: Encodable {
        let id: UUID
        let eventUID: String
        let assignee: UUID?

        enum CodingKeys: String, CodingKey {
            case id, assignee
            case eventUID = "event_uid"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(eventUID, forKey: .eventUID)
            try container.encode(assignee, forKey: .assignee)
        }
    }
}

extension SyncedTable where Change == EventAssigneeChange {
    func assignee(for eventUID: String?) -> UUID? {
        guard let eventUID else { return nil }
        return records.first { $0.eventUID == eventUID }?.assignee
    }

    func assign(_ eventUID: String, to assignee: UUID?) {
        let existing = records.first { $0.eventUID == eventUID }
        record(.set(EventAssignee(
            id: existing?.id ?? UUID(), eventUID: eventUID, assignee: assignee, createdAt: existing?.createdAt ?? .now
        )))
    }

    /// När händelsen raderas behövs inte raden längre.
    func forget(_ eventUID: String) {
        let ids = records.filter { $0.eventUID == eventUID }.map(\.id)
        guard !ids.isEmpty else { return }
        record(.remove(ids: ids))
    }
}
