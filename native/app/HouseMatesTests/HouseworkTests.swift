import XCTest
@testable import HouseMates

final class LocalDayTests: XCTestCase {
    func testAddingDaysKeepsThePlainDateAcrossTheSwitchToWinterTime() {
        XCTAssertEqual(LocalDay.adding(1, to: "2026-10-24"), "2026-10-25")
        XCTAssertEqual(LocalDay.adding(7, to: "2026-10-22"), "2026-10-29")
    }

    func testDaysUntilCountsFromTheStartOfToday() {
        let lateEvening = LocalDay.date(from: "2026-10-09")!.addingTimeInterval(23 * 3600)

        XCTAssertEqual(LocalDay.days(until: "2026-10-09", from: lateEvening), 0)
        XCTAssertEqual(LocalDay.days(until: "2026-10-10", from: lateEvening), 1)
        XCTAssertEqual(LocalDay.days(until: "2026-10-07", from: lateEvening), -2)
    }

    func testLabelSaysTodayTomorrowOrTheDate() {
        let today = LocalDay.date(from: "2026-10-07")!

        XCTAssertEqual(LocalDay.label("2026-10-07", from: today), "Idag")
        XCTAssertEqual(LocalDay.label("2026-10-08", from: today), "Imorgon")
        XCTAssertEqual(LocalDay.label("2026-10-06", from: today), "Igår")
        XCTAssertTrue(LocalDay.label("2026-10-09", from: today).contains("9 okt"))
    }
}

final class TodoChangeTests: XCTestCase {
    private let me = UUID()
    private let paint = Todo(
        id: UUID(), title: "Måla staketet", notes: nil, assignee: nil, startDate: nil, dueDate: nil,
        done: false, doneAt: nil, doneBy: nil, createdAt: .distantPast
    )

    func testMarkingDoneRemembersWhoAndUndoingForgetsIt() {
        var todos = [paint]

        TodoChange.setDone(id: paint.id, done: true, by: me).apply(to: &todos)
        XCTAssertEqual(todos[0].doneBy, me)
        XCTAssertNotNil(todos[0].doneAt)

        TodoChange.setDone(id: paint.id, done: false, by: me).apply(to: &todos)
        XCTAssertNil(todos[0].doneBy)
        XCTAssertNil(todos[0].doneAt)
    }

    func testAnUpdateCanRemoveTheDatesAndNotes() {
        var todos = [paint]
        TodoChange.update(
            id: paint.id, title: "Måla", notes: "Vit färg i förrådet", assignee: me, startDate: "2026-10-10", dueDate: "2026-10-12"
        ).apply(to: &todos)
        XCTAssertEqual(todos[0].notes, "Vit färg i förrådet")

        TodoChange.update(id: paint.id, title: "Måla", notes: nil, assignee: me, startDate: nil, dueDate: nil).apply(to: &todos)

        XCTAssertNil(todos[0].notes)
        XCTAssertNil(todos[0].startDate)
        XCTAssertNil(todos[0].dueDate)
        XCTAssertEqual(todos[0].assignee, me)
    }

    func testEmptyNotesAreNoNotes() {
        XCTAssertNil(TodoList.limited(notes: "  \n "))
        XCTAssertEqual(TodoList.limited(notes: " Ring före 12 \n"), "Ring före 12")
        XCTAssertEqual(TodoList.limited(notes: String(repeating: "a", count: 1200))?.count, 1000)
    }

    func testAQueueSavedBeforeNotesStillReadsBack() throws {
        let saved = #"[{"update":{"id":"\#(paint.id)","title":"Måla"}}]"#

        let decoded = try JSONDecoder().decode([TodoChange].self, from: Data(saved.utf8))

        XCTAssertEqual(decoded, [.update(id: paint.id, title: "Måla", notes: nil, assignee: nil, startDate: nil, dueDate: nil)])
    }

    func testTheQueueSurvivesBeingSavedAndReadBack() throws {
        let changes: [TodoChange] = [.add(paint), .setDone(id: paint.id, done: true, by: me), .remove(ids: [paint.id])]

        let decoded = try JSONDecoder().decode([TodoChange].self, from: JSONEncoder().encode(changes))

        XCTAssertEqual(decoded, changes)
    }
}

final class ChoreScheduleTests: XCTestCase {
    private let today = LocalDay.date(from: "2026-10-07")!.addingTimeInterval(10 * 3600)

    private func chore(interval: Int?, lastDone: String?, created: String = "2026-09-01") -> Chore {
        Chore(
            id: UUID(), title: "Dammsuga", assignee: nil, intervalDays: interval,
            lastDoneAt: lastDone.flatMap(LocalDay.date(from:))?.addingTimeInterval(20 * 3600),
            lastDoneBy: nil, createdAt: LocalDay.date(from: created)!
        )
    }

    func testTheDueDayCountsFromWhenItWasLastDone() {
        XCTAssertEqual(ChoreSchedule.dueDay(for: chore(interval: 7, lastDone: "2026-10-01")), "2026-10-08")
        XCTAssertEqual(ChoreSchedule.dueDay(for: chore(interval: 7, lastDone: nil, created: "2026-10-05")), "2026-10-12")
        XCTAssertNil(ChoreSchedule.dueDay(for: chore(interval: nil, lastDone: "2026-10-01")))
    }

    func testOverdueChoresComeFirstAndThoseWithoutIntervalLast() {
        let soon = chore(interval: 7, lastDone: "2026-10-05")
        let overdue = chore(interval: 7, lastDone: "2026-09-20")
        let whenever = chore(interval: nil, lastDone: "2026-09-01")

        XCTAssertEqual(ChoreSchedule.sorted([whenever, soon, overdue]).map(\.id), [overdue.id, soon.id, whenever.id])
    }

    func testIntervalLabels() {
        XCTAssertEqual(ChoreSchedule.intervalLabel(days: 7), "varje vecka")
        XCTAssertEqual(ChoreSchedule.intervalLabel(days: 14), "varannan vecka")
        XCTAssertEqual(ChoreSchedule.intervalLabel(days: 21), "var 3:e vecka")
        XCTAssertEqual(ChoreSchedule.intervalLabel(days: 1), "varje dag")
        XCTAssertEqual(ChoreSchedule.intervalLabel(days: 10), "var 10:e dag")
        XCTAssertEqual(ChoreSchedule.intervalLabel(days: 147), "var 21:a vecka")
    }

    func testLabelsForWhenItWasDoneAndWhenItIsDue() {
        let doneYesterday = chore(interval: 7, lastDone: "2026-10-06")
        let late = chore(interval: 7, lastDone: "2026-09-28")

        XCTAssertEqual(ChoreSchedule.lastDoneLabel(doneYesterday, today: today), "Gjord igår")
        XCTAssertEqual(ChoreSchedule.dueLabel(doneYesterday, today: today), "Om 6 dagar")
        XCTAssertEqual(ChoreSchedule.lastDoneLabel(late, today: today), "Gjord för 9 dagar sedan")
        XCTAssertEqual(ChoreSchedule.dueLabel(late, today: today), "Försenad 2 dagar")
        XCTAssertEqual(ChoreSchedule.lastDoneLabel(chore(interval: 7, lastDone: nil), today: today), "Aldrig gjord")
    }

    func testUndoingClearsWhoDidIt() {
        var chores = [chore(interval: 7, lastDone: "2026-10-06")]
        let me = UUID()

        ChoreChange.setLastDone(id: chores[0].id, at: .now, by: me).apply(to: &chores)
        XCTAssertEqual(chores[0].lastDoneBy, me)

        ChoreChange.setLastDone(id: chores[0].id, at: nil, by: me).apply(to: &chores)
        XCTAssertNil(chores[0].lastDoneAt)
        XCTAssertNil(chores[0].lastDoneBy)
    }
}

final class AssigneeFilterTests: XCTestCase {
    private let me = UUID()
    private let partner = UUID()

    func testEachFilterShowsOnlyItsOwn() {
        let assignees: [UUID?] = [me, partner, nil]

        XCTAssertEqual(assignees.filter(AssigneeFilter.everyone.includes), assignees)
        XCTAssertEqual(assignees.filter(AssigneeFilter.person(me).includes), [me])
        XCTAssertEqual(assignees.filter(AssigneeFilter.person(partner).includes), [partner])
        XCTAssertEqual(assignees.filter(AssigneeFilter.shared.includes), [nil])
    }
}

final class ChoreCalendarTests: XCTestCase {
    private func chore(_ title: String, interval: Int?, lastDone: String) -> Chore {
        Chore(
            id: UUID(), title: title, assignee: nil, intervalDays: interval,
            lastDoneAt: LocalDay.date(from: lastDone)!.addingTimeInterval(12 * 3600),
            lastDoneBy: nil, createdAt: .distantPast
        )
    }

    func testChoresAreOnTheirDueDayAndOverdueOnesOnToday() {
        let vacuum = chore("Dammsuga", interval: 7, lastDone: "2026-10-01")      // sista dag 8 okt
        let plants = chore("Vattna", interval: 3, lastDone: "2026-10-12")        // sista dag 15 okt
        let windows = chore("Putsa fönster", interval: nil, lastDone: "2026-09-01")

        let grid = ChoreSchedule.byDueDay([vacuum, plants, windows])
        XCTAssertEqual(grid.mapValues { $0.map(\.title) }, ["2026-10-08": ["Dammsuga"], "2026-10-15": ["Vattna"]])

        let list = ChoreSchedule.byDueDay([vacuum, plants, windows], overdueOn: "2026-10-13")
        XCTAssertEqual(list.mapValues { $0.map(\.title) }, ["2026-10-13": ["Dammsuga"], "2026-10-15": ["Vattna"]])
    }
}
