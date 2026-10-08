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

    func testOnlyAPermanentNoDropsAChange() {
        XCTAssertTrue(ShoppingList.isRejected(PostgrestError(code: "23505", message: "Dubblett")))
        XCTAssertTrue(ShoppingList.isRejected(PostgrestError(code: "42501", message: "Behörighet")))
        XCTAssertTrue(ShoppingList.isRejected(PostgrestError(code: "P0001", message: "Eget fel")))
        XCTAssertTrue(ShoppingList.isRejected(httpError(414)))
    }

    func testAServerThatDoesNotAnswerIsTriedAgain() {
        XCTAssertFalse(ShoppingList.isRejected(PostgrestError(message: "An invalid response was received from the upstream server")))
        XCTAssertFalse(ShoppingList.isRejected(PostgrestError(code: "PGRST000", message: "Ingen databas")))
        XCTAssertFalse(ShoppingList.isRejected(PostgrestError(code: "PGRST303", message: "Utgången inloggning")))
        XCTAssertFalse(ShoppingList.isRejected(httpError(503)))
        XCTAssertFalse(ShoppingList.isRejected(httpError(429)))
        XCTAssertFalse(ShoppingList.isRejected(URLError(.notConnectedToInternet)))
        XCTAssertFalse(ShoppingList.isRejected(CancellationError()))
    }

    func testBulkChangesAreSplitIntoParts() {
        let ids = (0..<120).map { _ in UUID() }

        let parts = ids.chunked(into: 50)

        XCTAssertEqual(parts.map(\.count), [50, 50, 20])
        XCTAssertEqual(parts.flatMap { $0 }, ids)
    }

    private func httpError(_ status: Int) -> HTTPError {
        HTTPError(data: Data(), response: HTTPURLResponse(url: URL(string: "https://exempel.se")!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    func testTheQueueSurvivesBeingSavedAndReadBack() throws {
        let changes: [ShoppingChange] = [.add(id: UUID(), name: "Kaffe", qty: nil, createdAt: .now), .remove(ids: [milk.id])]

        let decoded = try JSONDecoder().decode([ShoppingChange].self, from: JSONEncoder().encode(changes))

        XCTAssertEqual(decoded, changes)
    }
}
