import Foundation

struct Profile: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let color: String   // "#378ADD"; sätts när man skapar eller går med i ett hushåll
}

struct Household: Codable, Identifiable, Equatable {
    let id: UUID
    let inviteCode: String
    let calendarTitle: String?
    let calendarEventUIDs: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case inviteCode = "invite_code"
        case calendarTitle = "calendar_title"
        case calendarEventUIDs = "calendar_event_uids"
    }
}

struct ShoppingItem: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let qty: String?     // "500 g" när varan kommer från ett recept
    var checked: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, qty, checked
        case createdAt = "created_at"
    }
}

/// Flikarna. Råvärdet är samma som notisernas `url` (digest.ts), så ett tryck på en notis öppnar rätt flik.
enum AppTab: String {
    case shopping = "inkop"
    case todos = "todo"
    case calendar = "kalender"
    case settings = "installningar"
}
