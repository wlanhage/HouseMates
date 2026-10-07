import XCTest
@testable import HouseMates

/// Samma fall som webbappens tests/ingredients.test.ts, så att båda delar raderna likadant.
final class IngredientTests: XCTestCase {
    func testAQuantityIsSplitFromTheItem() {
        let cases: [(line: String, name: String, qty: String)] = [
            ("500 g köttfärs", "Köttfärs", "500 g"),
            ("2 msk olivolja", "Olivolja", "2 msk"),
            ("1 dl grädde", "Grädde", "1 dl"),
            ("0,5 dl mjölk", "Mjölk", "0,5 dl"),
            ("1 ½ dl vatten", "Vatten", "1 ½ dl"),
            ("½ citron", "Citron", "½"),
            ("1-2 tsk salt", "Salt", "1-2 tsk"),
            ("2 st ägg", "Ägg", "2 st"),
            ("3 ägg", "Ägg", "3"),
            ("1 gul lök", "Gul lök", "1"),
            ("2 vitlöksklyftor", "Vitlöksklyftor", "2"),
            ("1 burk krossade tomater", "Krossade tomater", "1 burk"),
            ("1 förp (400 g) krossade tomater", "Krossade tomater", "1 förp (400 g)"),
            ("ca 800 g potatis", "Potatis", "800 g"),
            ("2 dl  ris,  gärna basmati", "Ris, gärna basmati", "2 dl")
        ]
        for (line, name, qty) in cases {
            XCTAssertEqual(Ingredient(line: line), Ingredient(name: name, qty: qty), line)
        }
    }

    func testLinesWithoutAQuantityAreKeptButCapitalized() {
        XCTAssertEqual(Ingredient(line: "salt och peppar"), Ingredient(name: "Salt och peppar", qty: nil))
        XCTAssertEqual(Ingredient(line: "Mjölk"), Ingredient(name: "Mjölk", qty: nil))
    }

    func testOnlyAQuantityBecomesTheNameAsItIs() {
        XCTAssertEqual(Ingredient(line: "100 g"), Ingredient(name: "100 g", qty: nil))
    }

    func testTheUnitGIsNotFoundInsideWords() {
        XCTAssertEqual(Ingredient(line: "2 gula lökar"), Ingredient(name: "Gula lökar", qty: "2"))
    }
}

final class FavoriteTests: XCTestCase {
    func testItemsAreOnePerLineWithoutDuplicates() {
        XCTAssertEqual(Favorite.items(from: "500 g köttfärs\n Tortillas \n\nsalsa\nSalsa"), ["500 g köttfärs", "Tortillas", "salsa"])
        XCTAssertEqual(Favorite.items(from: "Mjölk\r\nÄgg"), ["Mjölk", "Ägg"])
    }

    func testACommaDoesNotSplitAnItem() {
        XCTAssertEqual(Favorite.items(from: "2 dl ris, gärna basmati"), ["2 dl ris, gärna basmati"])
    }

    func testHostLabelDropsWww() {
        XCTAssertEqual(hostLabel("https://www.ica.se/recept/chili-con-carne-424/"), "ica.se")
        XCTAssertEqual(hostLabel("https://koket.se/x"), "koket.se")
    }

    func testAnUpdateChangesNameAndItemsButKeepsTheSource() {
        let tacos = Favorite(
            id: UUID(), name: "Tacos", items: ["Tortillas"], imageURL: nil,
            sourceURL: "https://www.ica.se/recept/tacos-1/", createdAt: .distantPast
        )
        var favorites = [tacos]

        FavoriteChange.update(id: tacos.id, name: "Fredagstacos", items: ["Tortillas", "Salsa"]).apply(to: &favorites)

        XCTAssertEqual(favorites[0].name, "Fredagstacos")
        XCTAssertEqual(favorites[0].items, ["Tortillas", "Salsa"])
        XCTAssertEqual(favorites[0].sourceURL, tacos.sourceURL)
    }
}
