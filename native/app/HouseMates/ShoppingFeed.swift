import Foundation

/// En rad i aktivitetsloggen (`activity_log`), skriven av databasens triggers.
struct Activity: Decodable, Identifiable, Equatable {
    let id: Int
    let actor: UUID
    let type: String
    let payload: Payload?
    let createdAt: Date

    struct Payload: Decodable, Equatable {
        let name: String?
    }

    enum CodingKeys: String, CodingKey {
        case id, actor, type, payload
        case createdAt = "created_at"
    }
}

/// Flera händelser av samma slag från samma person, visade som en rad.
struct ActivityGroup: Identifiable, Equatable {
    let id: Int
    let actor: UUID
    let type: String
    var entries: [Activity]
    let newest: Date
}

/// Hems flöde över vad som lagts till och handlats. Samma gruppering som webbappens activityFeed.ts.
enum ShoppingFeed {
    static let types = ["shopping.added", "shopping.checked"]
    private static let window: TimeInterval = 30 * 60
    private static let verbs = ["shopping.added": "la till", "shopping.checked": "bockade av"]

    /// Samma person och typ inom 30 minuter blir en rad, även om andra rader ligger emellan.
    /// Raderna kommer med den senaste först.
    static func groups(_ activities: [Activity]) -> [ActivityGroup] {
        var groups: [ActivityGroup] = []
        var openGroup: [String: Int] = [:]
        for activity in activities {
            let key = "\(activity.actor)|\(activity.type)"
            if let index = openGroup[key], groups[index].newest.timeIntervalSince(activity.createdAt) <= window {
                groups[index].entries.append(activity)
            } else {
                openGroup[key] = groups.count
                groups.append(ActivityGroup(
                    id: activity.id, actor: activity.actor, type: activity.type,
                    entries: [activity], newest: activity.createdAt
                ))
            }
        }
        return groups
    }

    /// "la till Mjölk", "bockade av 3 varor"
    static func describe(_ group: ActivityGroup) -> String {
        let verb = verbs[group.type] ?? "ändrade"
        guard group.entries.count == 1 else { return "\(verb) \(group.entries.count) varor" }
        return "\(verb) \(group.entries[0].payload?.name ?? "en vara")"
    }
}
