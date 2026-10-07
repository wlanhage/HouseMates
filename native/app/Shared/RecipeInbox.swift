import Foundation

/// Receptlänkar som delats till HouseMates från Safari. Delningstillägget lägger dem här, i en
/// App Group som appen och tillägget delar, och appen hämtar recepten nästa gång den öppnas.
/// Tillägget har ingen inloggning, så själva hämtningen sker alltid i appen.
enum RecipeInbox {
    static let appGroup = "group.se.housemates.app"
    private static let key = "delade-recept"
    private static let defaults = UserDefaults(suiteName: appGroup)

    static var links: [String] {
        defaults?.stringArray(forKey: key) ?? []
    }

    static func add(_ link: String) {
        guard !links.contains(link) else { return }
        defaults?.set(links + [link], forKey: key)
    }

    static func remove(_ link: String) {
        defaults?.set(links.filter { $0 != link }, forKey: key)
    }

    static func clear() {
        defaults?.removeObject(forKey: key)
    }
}
