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

    /// "Anna la till Mjölk", "Du bockade av 3 varor". Hela meningen översätts, så att ordföljden
    /// kan vara en annan på engelska.
    static func describe(_ group: ActivityGroup, actor: String, in language: AppLanguage = .current) -> String {
        let count = group.entries.count
        let name = group.entries[0].payload?.name ?? String(appLocalized: "en vara", in: language)
        let sentence: LocalizedStringResource = switch (group.type, count) {
        case ("shopping.added", 1): "\(actor) la till \(name)"
        case ("shopping.added", _): "\(actor) la till \(count) varor"
        case ("shopping.checked", 1): "\(actor) bockade av \(name)"
        case ("shopping.checked", _): "\(actor) bockade av \(count) varor"
        case (_, 1): "\(actor) ändrade \(name)"
        default: "\(actor) ändrade \(count) varor"
        }
        return String(appLocalized: sentence, in: language)
    }
}
