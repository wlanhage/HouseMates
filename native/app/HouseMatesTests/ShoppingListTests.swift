import Supabase
import XCTest
@testable import HouseMates

final class ShoppingListTests: XCTestCase {
    private let milk = ShoppingItem(id: UUID(), name: "Mjölk", qty: nil, checked: false, createdAt: .distantPast)

    func testChangesMadeOfflineShowOnTopOfTheServersList() {
        let bread = UUID()
        let changes: [ShoppingChange] = [
            .add(id: bread, name: "Bröd", qty: nil, createdAt: .now),
            .setChecked(id: milk.id, checked: true)
        ]

        let shown = ShoppingList.applying(changes, to: [milk])

        XCTAssertEqual(shown.map(\.name), ["Mjölk", "Bröd"])
        XCTAssertEqual(shown.first?.checked, true)
    }

    func testAnAddAlreadyOnTheServerIsNotShownTwice() {
        let shown = ShoppingList.applying([.add(id: milk.id, name: "Mjölk", qty: nil, createdAt: .now)], to: [milk])

        XCTAssertEqual(shown.count, 1)
    }

    func testRemovingHidesTheItemsEvenIfAddedInTheSameQueue() {
        let bread = UUID()
        let changes: [ShoppingChange] = [
            .add(id: bread, name: "Bröd", qty: nil, createdAt: .now),
            .remove(ids: [bread, milk.id])
        ]

        XCTAssertTrue(ShoppingList.applying(changes, to: [milk]).isEmpty)
    }

    func testOnlyAnAnswerFromTheDatabaseDropsAChange() {
        XCTAssertTrue(ShoppingList.isRejected(PostgrestError(code: "23505", message: "Dubblett")))
        XCTAssertFalse(ShoppingList.isRejected(PostgrestError(message: "An invalid response was received from the upstream server")))
        XCTAssertFalse(ShoppingList.isRejected(URLError(.notConnectedToInternet)))
        XCTAssertFalse(ShoppingList.isRejected(CancellationError()))
    }

    func testTheQueueSurvivesBeingSavedAndReadBack() throws {
        let changes: [ShoppingChange] = [.add(id: UUID(), name: "Kaffe", qty: nil, createdAt: .now), .remove(ids: [milk.id])]

        let decoded = try JSONDecoder().decode([ShoppingChange].self, from: JSONEncoder().encode(changes))

        XCTAssertEqual(decoded, changes)
    }
}
