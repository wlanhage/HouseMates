import XCTest
@testable import HouseMates

/// Engelskan kommer från Localizable.xcstrings i appen, så de här testerna visar också att
/// översättningarna finns och att argumenten hamnar rätt.
final class LanguageTests: XCTestCase {
    private let today = LocalDay.date(from: "2026-10-07")!.addingTimeInterval(10 * 3600)

    private func chore(interval: Int?, lastDone: String?) -> Chore {
        Chore(
            id: UUID(), title: "Dammsuga", assignee: nil, intervalDays: interval,
            lastDoneAt: lastDone.flatMap(LocalDay.date(from:))?.addingTimeInterval(20 * 3600),
            lastDoneBy: nil, createdAt: LocalDay.date(from: "2026-09-01")!
        )
    }

    func testASavedChoiceWins() {
        XCTAssertEqual(AppLanguage(saved: "en"), .english)
        XCTAssertEqual(AppLanguage(saved: "sv"), .swedish)
    }

    func testTextBuiltInCodeIsTranslated() {
        XCTAssertEqual(String(appLocalized: "Tog bort \("Mjölk")", in: .english), "Removed Mjölk")
        XCTAssertEqual(String(appLocalized: "Tog bort \("Mjölk")", in: .swedish), "Tog bort Mjölk")
        XCTAssertEqual(itemCountLabel(1, in: .english), "1 item")
        XCTAssertEqual(itemCountLabel(3, in: .english), "3 items")
        XCTAssertEqual(itemCountLabel(3, in: .swedish), "3 varor")
    }

    func testChoreLabelsInEnglish() {
        XCTAssertEqual(ChoreSchedule.intervalLabel(days: 7, in: .english), "every week")
        XCTAssertEqual(ChoreSchedule.intervalLabel(days: 14, in: .english), "every other week")
        XCTAssertEqual(ChoreSchedule.intervalLabel(days: 147, in: .english), "every 21 weeks")
        XCTAssertEqual(ChoreSchedule.intervalLabel(days: 10, in: .english), "every 10 days")

        let doneYesterday = chore(interval: 7, lastDone: "2026-10-06")
        let late = chore(interval: 7, lastDone: "2026-09-28")
        XCTAssertEqual(ChoreSchedule.lastDoneLabel(doneYesterday, by: "Anna", today: today, in: .english), "Done yesterday by Anna")
        XCTAssertEqual(ChoreSchedule.lastDoneLabel(late, today: today, in: .english), "Done 9 days ago")
        XCTAssertEqual(ChoreSchedule.dueLabel(doneYesterday, today: today, in: .english), "In 6 days")
        XCTAssertEqual(ChoreSchedule.dueLabel(late, today: today, in: .english), "2 days overdue")
        XCTAssertEqual(ChoreSchedule.lastDoneLabel(chore(interval: 7, lastDone: nil), today: today, in: .english), "Never done")
    }

    func testWhoDidItIsPartOfTheSentence() {
        let doneYesterday = chore(interval: 7, lastDone: "2026-10-06")

        XCTAssertEqual(ChoreSchedule.lastDoneLabel(doneYesterday, by: "Anna", today: today, in: .swedish), "Gjord igår av Anna")
    }

    func testDaysInEnglish() {
        XCTAssertEqual(LocalDay.label("2026-10-07", from: today, in: .english), "Today")
        XCTAssertEqual(LocalDay.label("2026-10-08", from: today, in: .english), "Tomorrow")
        XCTAssertEqual(LocalDay.label("2026-10-06", from: today, in: .english), "Yesterday")
        // Ordningen beror på telefonens region ("Fri 9 Oct" i Sverige, "Fri, Oct 9" i USA).
        let date = LocalDay.label("2026-10-09", from: today, in: .english)
        XCTAssertTrue(date.contains("Fri") && date.contains("Oct") && date.contains("9"), date)
    }

    func testAPeriodKeepsCapitalsOnlyInEnglish() {
        XCTAssertEqual(LocalDay.period(from: "2026-10-07", to: "2026-10-08", today: today, in: .swedish), "Idag–imorgon")
        XCTAssertEqual(LocalDay.period(from: "2026-10-07", to: "2026-10-08", today: today, in: .english), "Today–Tomorrow")
    }

    func testTheFeedSentenceInEnglish() {
        let milk = Activity(id: 1, actor: UUID(), type: "shopping.added", payload: .init(name: "Mjölk"), createdAt: today)
        let group = ShoppingFeed.groups([milk])[0]

        XCTAssertEqual(ShoppingFeed.describe(group, actor: "You", in: .english), "You added Mjölk")
    }

    func testTheMonthInEnglish() {
        let month = MonthGrid(year: 2026, month: 10, language: .english)

        XCTAssertEqual(month.title, "October 2026")
        XCTAssertEqual(MonthGrid.weekdays(in: .english).first, "Mon")
        XCTAssertEqual(MonthGrid.weekdays(in: .swedish).first, "mån")
    }

    func testServerMessagesAreTranslatedWhenKnown() {
        XCTAssertEqual(AppLanguage.english.translated("Du är redan med i ett hushåll"), "You're already in a household")
        XCTAssertEqual(AppLanguage.swedish.translated("Du är redan med i ett hushåll"), "Du är redan med i ett hushåll")
        XCTAssertEqual(AppLanguage.english.translated("Ett okänt fel"), "Ett okänt fel")
    }
}
