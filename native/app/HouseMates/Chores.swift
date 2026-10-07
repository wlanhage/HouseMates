import Foundation
import Supabase

struct Chore: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var assignee: UUID?          // nil = gemensamt
    var intervalDays: Int?
    var lastDoneAt: Date?
    var lastDoneBy: UUID?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, assignee
        case intervalDays = "interval_days"
        case lastDoneAt = "last_done_at"
        case lastDoneBy = "last_done_by"
        case createdAt = "created_at"
    }
}

/// Hushållets städsysslor; kön och synken finns i `SyncedTable`.
typealias ChoreList = SyncedTable<ChoreChange>

enum ChoreChange: TableChange {
    case add(id: UUID, title: String, assignee: UUID?, intervalDays: Int?, createdAt: Date)
    case update(id: UUID, title: String, assignee: UUID?, intervalDays: Int?)
    /// Gjord nu, ett annat datum eller ångrad. Servern sätter vem som gjorde den när datumet blir senare.
    case setLastDone(id: UUID, at: Date?, by: UUID?)
    case remove(ids: [UUID])

    static let table = "chores"
    static let columns = "id, title, assignee, interval_days, last_done_at, last_done_by, created_at"

    func apply(to chores: inout [Chore]) {
        switch self {
        case let .add(id, title, assignee, intervalDays, createdAt):
            if !chores.contains(where: { $0.id == id }) {
                chores.append(Chore(
                    id: id, title: title, assignee: assignee, intervalDays: intervalDays,
                    lastDoneAt: nil, lastDoneBy: nil, createdAt: createdAt
                ))
            }
        case let .update(id, title, assignee, intervalDays):
            guard let index = chores.firstIndex(where: { $0.id == id }) else { return }
            chores[index].title = title
            chores[index].assignee = assignee
            chores[index].intervalDays = intervalDays
        case let .setLastDone(id, at, by):
            guard let index = chores.firstIndex(where: { $0.id == id }) else { return }
            chores[index].lastDoneAt = at
            chores[index].lastDoneBy = at == nil ? nil : by
        case let .remove(ids):
            chores.removeAll { ids.contains($0.id) }
        }
    }

    func send(to table: PostgrestQueryBuilder) async throws {
        switch self {
        case let .add(id, title, assignee, intervalDays, _):
            try await table.insert(ChoreFields(id: id, title: title, assignee: assignee, intervalDays: intervalDays)).execute()
        case let .update(id, title, assignee, intervalDays):
            try await table.update(ChoreFields(id: nil, title: title, assignee: assignee, intervalDays: intervalDays))
                .eq("id", value: id).execute()
        case let .setLastDone(id, at, by):
            try await table.update(LastDone(at: at, by: at == nil ? nil : by)).eq("id", value: id).execute()
        case let .remove(ids):
            try await table.update(["deleted_at": Date.now]).in("id", values: ids).execute()
        }
    }

    /// Tomma fält skickas som null, så att ett borttaget intervall också försvinner på servern.
    private struct ChoreFields: Encodable {
        let id: UUID?
        let title: String
        let assignee: UUID?
        let intervalDays: Int?

        enum CodingKeys: String, CodingKey {
            case id, title, assignee
            case intervalDays = "interval_days"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(title, forKey: .title)
            try container.encode(assignee, forKey: .assignee)
            try container.encode(intervalDays, forKey: .intervalDays)
        }
    }

    private struct LastDone: Encodable {
        let at: Date?
        let by: UUID?

        enum CodingKeys: String, CodingKey {
            case at = "last_done_at"
            case by = "last_done_by"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(at, forKey: .at)
            try container.encode(by, forKey: .by)
        }
    }
}

/// Städsysslornas sista dag och texter (samma regler som webbappens chores.ts).
enum ChoreSchedule {
    /// Sista dag räknas från när sysslan faktiskt gjordes, så att intervallet aldrig blir längre än
    /// angivet. En syssla som aldrig gjorts räknas från när den lades till.
    static func dueDay(for chore: Chore) -> String? {
        guard let interval = chore.intervalDays else { return nil }
        return LocalDay.adding(interval, to: LocalDay.string(from: chore.lastDoneAt ?? chore.createdAt))
    }

    /// Sysslor med sista dag först (försenade överst), sedan de som gjordes för längst sedan.
    static func sorted(_ chores: [Chore]) -> [Chore] {
        chores.sorted { a, b in
            switch (dueDay(for: a), dueDay(for: b)) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return (a.lastDoneAt ?? .distantPast) < (b.lastDoneAt ?? .distantPast)
            }
        }
    }

    /// "varje vecka", "varannan vecka", "var 3:e vecka", "var 10:e dag"
    static func intervalLabel(days: Int) -> String {
        let (count, unit) = days % 7 == 0 ? (days / 7, "vecka") : (days, "dag")
        switch count {
        case 1: return "varje \(unit)"
        case 2: return "varannan \(unit)"
        default: return "var \(ordinal(count)) \(unit)"
        }
    }

    /// Dagar sedan sysslan senast gjordes: 0 idag, 1 igår.
    static func daysSinceDone(_ chore: Chore, today: Date = .now) -> Int? {
        guard let lastDoneAt = chore.lastDoneAt else { return nil }
        return LocalDay.days(until: LocalDay.string(from: lastDoneAt), from: today).map { -$0 }
    }

    /// Dagar kvar till sista dag: 0 idag, negativt när sysslan är försenad.
    static func daysLeft(_ chore: Chore, today: Date = .now) -> Int? {
        dueDay(for: chore).flatMap { LocalDay.days(until: $0, from: today) }
    }

    /// "Gjord idag", "Gjord igår", "Gjord för 5 dagar sedan", "Aldrig gjord"
    static func lastDoneLabel(_ chore: Chore, today: Date = .now) -> String {
        guard let days = daysSinceDone(chore, today: today) else { return "Aldrig gjord" }
        switch days {
        case ...0: return "Gjord idag"
        case 1: return "Gjord igår"
        default: return "Gjord för \(days) dagar sedan"
        }
    }

    /// "Idag", "Imorgon", "Om 3 dagar", "Försenad 2 dagar"
    static func dueLabel(_ chore: Chore, today: Date = .now) -> String? {
        guard let days = daysLeft(chore, today: today) else { return nil }
        switch days {
        case 0: return "Idag"
        case 1: return "Imorgon"
        case 2...: return "Om \(days) dagar"
        case -1: return "Försenad 1 dag"
        default: return "Försenad \(-days) dagar"
        }
    }

    /// 1:a, 2:a, 3:e, 11:e, 21:a
    private static func ordinal(_ n: Int) -> String {
        let lastTwo = n % 100
        let suffix = [1, 2].contains(n % 10) && lastTwo != 11 && lastTwo != 12 ? "a" : "e"
        return "\(n):\(suffix)"
    }
}

extension SyncedTable where Change == ChoreChange {
    var sorted: [Chore] { ChoreSchedule.sorted(records) }

    func add(title: String, assignee: UUID?, intervalDays: Int?) {
        record(.add(id: UUID(), title: title, assignee: assignee, intervalDays: intervalDays, createdAt: .now))
    }

    func update(_ chore: Chore, title: String, assignee: UUID?, intervalDays: Int?) {
        record(.update(id: chore.id, title: title, assignee: assignee, intervalDays: intervalDays))
    }

    func markDone(_ chore: Chore, by me: UUID?) {
        record(.setLastDone(id: chore.id, at: .now, by: me))
    }

    /// Ångra en avbockning eller rätta när den gjordes.
    func setLastDone(_ chore: Chore, at date: Date?, by: UUID?) {
        record(.setLastDone(id: chore.id, at: date, by: by))
    }

    func remove(_ chore: Chore) {
        record(.remove(ids: [chore.id]))
    }
}
