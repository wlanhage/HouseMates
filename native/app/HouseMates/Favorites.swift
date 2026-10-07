import Foundation
import Supabase

/// En rätt i Våra middagar. Ingredienserna sparas som råa rader ("500 g köttfärs") och delas i
/// vara och mängd först när de läggs på inköpslistan.
struct Favorite: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var items: [String]
    let imageURL: String?
    let sourceURL: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, items
        case imageURL = "image_url"
        case sourceURL = "source_url"
        case createdAt = "created_at"
    }

    /// En vara per rad; dubbletter tas bort. Kommatecken delar inte, eftersom en rad som
    /// "2 dl ris, gärna basmati" är en vara.
    static func items(from text: String) -> [String] {
        var seen = Set<String>()
        return text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}

/// "1 vara", "8 varor"
func itemCountLabel(_ count: Int) -> String {
    count == 1 ? "1 vara" : "\(count) varor"
}

/// "ica.se" ur "https://www.ica.se/recept/…"
func hostLabel(_ address: String) -> String {
    URL(string: address)?.host()?.replacingOccurrences(of: "www.", with: "", options: .anchored) ?? address
}

/// Hushållets middagar; kön och synken finns i `SyncedTable`.
typealias FavoriteList = SyncedTable<FavoriteChange>

enum FavoriteChange: TableChange {
    case add(Favorite)
    case update(id: UUID, name: String, items: [String])
    case remove(ids: [UUID])

    static let table = "favorites"
    static let columns = "id, name, items, image_url, source_url, created_at"

    func apply(to favorites: inout [Favorite]) {
        switch self {
        case let .add(favorite):
            if !favorites.contains(where: { $0.id == favorite.id }) { favorites.append(favorite) }
        case let .update(id, name, items):
            guard let index = favorites.firstIndex(where: { $0.id == id }) else { return }
            favorites[index].name = name
            favorites[index].items = items
        case let .remove(ids):
            favorites.removeAll { ids.contains($0.id) }
        }
    }

    func send(to table: PostgrestQueryBuilder) async throws {
        switch self {
        case let .add(favorite):
            try await table.insert(NewFavorite(
                id: favorite.id, name: favorite.name, items: favorite.items,
                imageURL: favorite.imageURL, sourceURL: favorite.sourceURL
            )).execute()
        case let .update(id, name, items):
            try await table.update(Contents(name: name, items: items)).eq("id", value: id).execute()
        case let .remove(ids):
            try await table.update(["deleted_at": Date.now]).in("id", values: ids).execute()
        }
    }

    private struct NewFavorite: Encodable {
        let id: UUID
        let name: String
        let items: [String]
        let imageURL: String?
        let sourceURL: String?

        enum CodingKeys: String, CodingKey {
            case id, name, items
            case imageURL = "image_url"
            case sourceURL = "source_url"
        }
    }

    private struct Contents: Encodable {
        let name: String
        let items: [String]
    }
}

extension SyncedTable where Change == FavoriteChange {
    var byName: [Favorite] {
        records.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    func favorite(_ id: UUID) -> Favorite? {
        records.first { $0.id == id }
    }

    func contains(sourceURL: String) -> Bool {
        records.contains { $0.sourceURL == sourceURL }
    }

    @discardableResult
    func add(name: String, items: [String], imageURL: String?, sourceURL: String?) -> UUID {
        let favorite = Favorite(
            id: UUID(), name: Self.limited(name), items: Self.limited(items),
            imageURL: imageURL, sourceURL: sourceURL, createdAt: .now
        )
        record(.add(favorite))
        return favorite.id
    }

    func update(_ favorite: Favorite, name: String, items: [String]) {
        record(.update(id: favorite.id, name: Self.limited(name), items: Self.limited(items)))
    }

    // Databasen tar namn på högst 120 tecken och högst 100 varor.
    private static func limited(_ name: String) -> String { String(name.prefix(120)) }
    private static func limited(_ items: [String]) -> [String] { Array(items.prefix(100)) }

    func remove(_ favorite: Favorite) {
        record(.remove(ids: [favorite.id]))
    }
}
