import Foundation

/// En ingrediensrad delad i vara och mängd: "500 g köttfärs" blir "Köttfärs" och "500 g". Så
/// hamnar ett recept på inköpslistan som "Köttfärs · 500 g", och listans dubblettregel (som
/// jämför namnet) fungerar fortfarande. Samma regler som webbappens ingredients.ts.
struct Ingredient: Equatable {
    let name: String
    let qty: String?
}

extension Ingredient {
    /// Rader utan mängd lämnas som de är, men får stor bokstav.
    init(line: String) {
        let text = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let match = Self.pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let rest = Self.group("rest", in: match, of: text)?.trimmingCharacters(in: .whitespaces),
              !rest.isEmpty else {
            self.init(name: Self.capitalized(text), qty: nil)
            return
        }
        let number = Self.group("num", in: match, of: text)?
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let qty = [number, Self.group("unit", in: match, of: text)?.lowercased(), Self.group("paren", in: match, of: text)]
            .compactMap { $0 }
            .joined(separator: " ")
        self.init(name: Self.capitalized(rest), qty: qty)
    }

    // Längsta först, så att till exempel "dl" inte matchas som "d" och en rest.
    private static let units = [
        "förpackningar", "förpackning", "portioner", "stycken", "flaskor", "flaska", "skivor",
        "klyftor", "kvistar", "burkar", "droppar", "paket", "påsar", "krukor", "klyfta", "skiva",
        "kvist", "kruka", "knippe", "tärning", "bitar", "förp", "burk", "påse", "nypa", "port",
        "blad", "msk", "tsk", "krm", "bit", "ark", "kg", "hg", "dl", "cl", "ml", "cm", "st", "g", "l"
    ]

    private static let number = #"(?:\d+(?:[.,]\d+)?(?:\s*/\s*\d+)?|[½¼¾⅓⅔⅛])"#

    private static let pattern = try! NSRegularExpression(
        pattern: #"^(?:ca\.?|cirka)?\s*"#
            + #"(?<num>\#(number)(?:\s*[-–]\s*\#(number))?(?:\s+[½¼¾⅓⅔⅛])?)"#
            + #"(?:\s*(?<unit>\#(units.joined(separator: "|")))\.?(?=\s|$|\())?"#
            + #"\s*(?<paren>\([^)]*\))?"#
            + #"\s*(?<rest>.*)$"#,
        options: .caseInsensitive
    )

    private static func group(_ name: String, in match: NSTextCheckingResult, of text: String) -> String? {
        Range(match.range(withName: name), in: text).map { String(text[$0]) }
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
