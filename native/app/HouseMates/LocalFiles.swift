import Foundation

/// Det appen sparar på telefonen, i en egen mapp som rensas vid utloggning, när man lämnar
/// hushållet och när kontot raderas.
enum LocalFiles {
    private static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "HouseMates", directoryHint: .isDirectory)
    }

    static func read<Value: Decodable>(_ type: Value.Type, from name: String) -> Value? {
        guard let data = try? Data(contentsOf: directory.appending(path: name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Filen är en reserv för när nätet saknas; misslyckas skrivningen hämtas listan från servern som vanligt.
    static func write(_ value: some Encodable, to name: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(value).write(to: directory.appending(path: name), options: .atomic)
    }

    /// Också receptlänkar som delats från Safari men inte hämtats än.
    static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        RecipeInbox.clear()
    }
}
