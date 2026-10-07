import Foundation
import Supabase

/// Ett recept som edge function `recipe-import` har läst från en receptsida.
struct ImportedRecipe: Decodable {
    let name: String
    let items: [String]
    let imageURL: String?
    let sourceURL: String

    enum CodingKeys: String, CodingKey {
        case name, items
        case imageURL = "image_url"
        case sourceURL = "source_url"
    }
}

enum RecipeImport {
    /// Servern hämtar sidan, eftersom appen inte ska behöva tolka varje sajt själv.
    static func fetch(_ link: String) async throws -> ImportedRecipe {
        struct Reply: Decodable { let recipe: ImportedRecipe }
        let reply: Reply = try await Backend.client.functions.invoke(
            "recipe-import",
            options: FunctionInvokeOptions(body: ["url": link])
        )
        return reply.recipe
    }
}

extension SyncedTable where Change == FavoriteChange {
    /// Hämtar recepten som delats från Safari och sparar dem. Utan nät ligger länkarna kvar till
    /// nästa gång. En sida som inte går att läsa sparas ändå, med sajtens namn, så att länken
    /// inte försvinner; varorna kan fyllas i för hand.
    func importSharedLinks() async {
        for link in RecipeInbox.links {
            do {
                let recipe = try await RecipeImport.fetch(link)
                if !contains(sourceURL: recipe.sourceURL) {
                    add(name: recipe.name, items: recipe.items, imageURL: recipe.imageURL, sourceURL: recipe.sourceURL)
                }
            } catch is URLError {
                return
            } catch {
                if !contains(sourceURL: link) {
                    add(name: hostLabel(link), items: [], imageURL: nil, sourceURL: link)
                }
            }
            RecipeInbox.remove(link)
        }
    }
}
