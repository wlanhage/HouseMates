import EventKit
import XCTest
@testable import HouseMates

final class SharedCalendarTests: XCTestCase {
    private let store = EKEventStore()

    private func event(start: Date, end: Date, allDay: Bool = false) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.startDate = start
        event.endDate = end
        event.isAllDay = allDay
        return event
    }

    func testAnEventThatStartedBeforeTodayIsShownToday() {
        let today = Calendar.current.startOfDay(for: .now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        let days = SharedCalendar.groupByDay([event(start: yesterday, end: tomorrow)], from: .now)

        XCTAssertEqual(days.map(\.day), [today])
    }

    func testDaysAreInOrderAndEventsWithinADayByStartTime() {
        let today = Calendar.current.startOfDay(for: .now)
        let later = event(start: today.addingTimeInterval(36 * 3600), end: today.addingTimeInterval(37 * 3600))
        let lateToday = event(start: today.addingTimeInterval(20 * 3600), end: today.addingTimeInterval(21 * 3600))
        let earlyToday = event(start: today.addingTimeInterval(8 * 3600), end: today.addingTimeInterval(9 * 3600))

        let days = SharedCalendar.groupByDay([later, lateToday, earlyToday], from: today)

        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].events, [earlyToday, lateToday])
    }

    /// Notisen bygger på samma format som webbappen: datum för heldag, ISO-tid annars.
    func testActivityStartIsADateForAllDayEventsAndATimeOtherwise() {
        let start = ISO8601DateFormatter().date(from: "2026-10-07T12:00:00Z")!

        XCTAssertEqual(
            SharedCalendar.activityStart(for: event(start: start, end: start.addingTimeInterval(3600))),
            "2026-10-07T12:00:00Z"
        )
        XCTAssertTrue(
            SharedCalendar.activityStart(for: event(start: start, end: start, allDay: true))
                .range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
        )
    }
}

final class ClockTimeTests: XCTestCase {
    func testAClockTimeSurvivesTheRoundTrip() {
        XCTAssertEqual(ClockTime.string(from: ClockTime.date(from: "07:30")), "07:30")
        XCTAssertEqual(ClockTime.string(from: ClockTime.date(from: "22:05")), "22:05")
    }
}

final class MarkdownBlockTests: XCTestCase {
    func testThePolicyIsSplitIntoHeadingsBulletsAndParagraphs() {
        let blocks = MarkdownBlock.parse("""
        # Rubrik

        Ett stycke
        på två rader.

        ## Del
        - punkt ett
        - punkt **två**
        """)

        XCTAssertEqual(blocks.map(\.kind), [.title, .paragraph, .heading, .bullet, .bullet])
        XCTAssertEqual(blocks[1].text, "Ett stycke på två rader.")
        XCTAssertEqual(blocks[4].text, "punkt **två**")
    }

    func testThePolicyFileIsBundledWithTheApp() {
        let url = Bundle(for: AppSession.self).url(forResource: "integritetspolicy", withExtension: "md")
            ?? Bundle.main.url(forResource: "integritetspolicy", withExtension: "md")

        XCTAssertNotNil(url)
    }
}
