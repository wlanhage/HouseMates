import EventKit
import XCTest
@testable import HouseMates

/// Samma fall som webbappens tests/monthGrid.test.ts.
final class MonthGridTests: XCTestCase {
    func testSeptember2026StartsOnATuesday() {
        let month = MonthGrid(year: 2026, month: 9, language: .swedish)

        XCTAssertEqual(month.title, "September 2026")
        XCTAssertEqual(month.first, "2026-09-01")
        XCTAssertEqual(month.last, "2026-09-30")
        XCTAssertNil(month.days[0])
        XCTAssertEqual(month.days[1], "2026-09-01")
        XCTAssertEqual(month.days.count, 31)
    }

    func testFebruary2026StartsOnASunday() {
        let month = MonthGrid(year: 2026, month: 2)

        XCTAssertEqual(month.days.filter { $0 == nil }.count, 6)
        XCTAssertEqual(month.days.compactMap { $0 }.count, 28)
    }

    func testWeeksAreSevenDaysEach() {
        let weeks = MonthGrid(year: 2026, month: 11).weeks

        XCTAssertEqual(weeks.count, 6)
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
        XCTAssertEqual(weeks[0].last, "2026-11-01")
        XCTAssertEqual(weeks[5].first, "2026-11-30")
    }

    func testAddingMonthsRollsOverTheYearBothWays() {
        XCTAssertEqual(MonthGrid(year: 2026, month: 12).adding(months: 1), MonthGrid(year: 2027, month: 1))
        XCTAssertEqual(MonthGrid(year: 2026, month: 1).adding(months: -1), MonthGrid(year: 2025, month: 12))
        XCTAssertEqual(MonthGrid(year: 2026, month: 9).adding(months: 5), MonthGrid(year: 2027, month: 2))
    }

    func testTheMonthContainingADay() {
        XCTAssertEqual(MonthGrid(containing: "2026-09-07"), MonthGrid(year: 2026, month: 9))
    }
}

/// Samma fall som webbappens tests/activity-feed.test.ts.
final class ShoppingFeedTests: XCTestCase {
    private let anna = UUID()
    private var sequence = 0
    private let noon = LocalDay.date(from: "2026-07-21")!.addingTimeInterval(12 * 3600)

    private func activity(_ type: String, _ name: String, minutesAgo: Double) -> Activity {
        sequence += 1
        return Activity(
            id: sequence, actor: anna, type: type, payload: .init(name: name),
            createdAt: noon.addingTimeInterval(-minutesAgo * 60)
        )
    }

    func testTheSameKindIsGroupedEvenWhenInterleaved() {
        let feed = [
            activity("shopping.added", "Ägg", minutesAgo: 8),
            activity("shopping.checked", "Socker", minutesAgo: 8),
            activity("shopping.added", "Kaffe", minutesAgo: 8),
            activity("shopping.checked", "Kaffe", minutesAgo: 9),
            activity("shopping.added", "Socker", minutesAgo: 9)
        ]

        let groups = ShoppingFeed.groups(feed)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map { ShoppingFeed.describe($0, actor: "Anna", in: .swedish) }, ["Anna la till 3 varor", "Anna bockade av 2 varor"])
    }

    func testASingleItemIsNamed() {
        let groups = ShoppingFeed.groups([activity("shopping.added", "Mjölk", minutesAgo: 2)])

        XCTAssertEqual(groups.map { ShoppingFeed.describe($0, actor: "Anna", in: .swedish) }, ["Anna la till Mjölk"])
    }

    func testMoreThanHalfAnHourApartAreSeparateRows() {
        let groups = ShoppingFeed.groups([
            activity("shopping.added", "Mjölk", minutesAgo: 1),
            activity("shopping.added", "Bröd", minutesAgo: 45)
        ])

        XCTAssertEqual(groups.count, 2)
    }
}

final class EventsByDayTests: XCTestCase {
    private let store = EKEventStore()

    private func event(_ start: String, _ startHour: Double, _ end: String, _ endHour: Double, allDay: Bool = false) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.startDate = LocalDay.date(from: start)!.addingTimeInterval(startHour * 3600)
        event.endDate = LocalDay.date(from: end)!.addingTimeInterval(endHour * 3600)
        event.isAllDay = allDay
        return event
    }

    func testAnEventOverSeveralDaysIsOnEachDayWithinTheRange() {
        let trip = event("2026-10-02", 18, "2026-10-05", 12)

        let days = SharedCalendar.byDay([trip], from: "2026-10-03", through: "2026-10-31")

        XCTAssertEqual(days.keys.sorted(), ["2026-10-03", "2026-10-04", "2026-10-05"])
    }

    func testAnEventEndingAtMidnightIsNotOnTheNextDay() {
        let party = event("2026-10-09", 20, "2026-10-10", 0)

        XCTAssertEqual(SharedCalendar.byDay([party], from: "2026-10-01", through: "2026-10-31").keys.sorted(), ["2026-10-09"])
    }

    func testAllDayEventsComeFirst() {
        let lunch = event("2026-10-09", 12, "2026-10-09", 13)
        let birthday = event("2026-10-09", 0, "2026-10-09", 23.99, allDay: true)

        let day = SharedCalendar.byDay([lunch, birthday], from: "2026-10-09", through: "2026-10-09")["2026-10-09"]

        XCTAssertEqual(day?.map(\.isAllDay), [true, false])
    }
}

final class EventAssigneeTests: XCTestCase {
    func testSettingAgainReplacesThePersonInsteadOfAddingARow() {
        let row = EventAssignee(id: UUID(), eventUID: "abc", assignee: UUID(), createdAt: .now)
        var rows = [row]

        EventAssigneeChange.set(EventAssignee(id: row.id, eventUID: "abc", assignee: nil, createdAt: row.createdAt))
            .apply(to: &rows)

        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0].assignee)
    }
}

/// Samma regler som webbappens dagsbläddring på hemskärmen.
final class HomeDayTests: XCTestCase {
    private func todo(_ title: String, start: String? = nil, due: String?) -> Todo {
        Todo(
            id: UUID(), title: title, notes: nil, assignee: nil, startDate: start, dueDate: due,
            done: false, doneAt: nil, doneBy: nil, createdAt: .distantPast
        )
    }

    func testTodayAlsoShowsOverdueButOtherDaysOnlyTheirOwn() {
        let open = [
            todo("Försenad", due: "2026-10-10"),
            todo("Idag", due: "2026-10-13"),
            todo("Helgen", start: "2026-10-17", due: "2026-10-18"),
            todo("Någon gång", due: nil)
        ]

        XCTAssertEqual(HomeDay.todos(open, on: "2026-10-13", today: "2026-10-13").map(\.title), ["Försenad", "Idag"])
        XCTAssertEqual(HomeDay.todos(open, on: "2026-10-10", today: "2026-10-13").map(\.title), ["Försenad"])
        XCTAssertEqual(HomeDay.todos(open, on: "2026-10-17", today: "2026-10-13").map(\.title), [])
        XCTAssertEqual(HomeDay.todos(open, on: "2026-10-18", today: "2026-10-13").map(\.title), ["Helgen"])
    }

    func testBrowsingGoesAWeekBackAndSixWeeksAhead() {
        XCTAssertEqual(HomeDay.offsets.lowerBound, -7)
        XCTAssertEqual(HomeDay.offsets.upperBound, 42)
    }
}
