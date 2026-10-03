import EventKit
import Observation
import OSLog
import UIKit

/// All EventKit experiments in one place, so the view only wires buttons to methods.
@MainActor
@Observable
final class CalendarLab {
    private let store = EKEventStore()
    private let logger = Logger(subsystem: "se.housemates.kalenderspike", category: "lab")

    private(set) var hasAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    private(set) var calendars: [EKCalendar] = []
    private(set) var log: [String] = []
    private(set) var linkToken: String?
    var selectedCalendarID: String?

    var selectedCalendar: EKCalendar? {
        calendars.first { $0.calendarIdentifier == selectedCalendarID }
    }

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.note("Kalenderdatabasen ändrades")
                self?.reload()
            }
        }
        reload()
    }

    func requestAccess() async {
        do {
            hasAccess = try await store.requestFullAccessToEvents()
            note(hasAccess ? "Fullständig åtkomst beviljad" : "Åtkomst nekad")
            reload()
        } catch {
            note("Fel vid åtkomstbegäran: \(error.localizedDescription)")
        }
    }

    func refresh() {
        store.refreshSourcesIfNecessary()
        reload()
    }

    func reload() {
        guard hasAccess else { return }
        calendars = store.calendars(for: .event).sorted {
            ($0.source.title, $0.title) < ($1.source.title, $1.title)
        }
        let summary = calendars.map { "\($0.title) [\($0.source.title)/\($0.source.sourceType.name)\($0.isSubscribed ? "/prenumererad" : "")\($0.allowsContentModifications ? "" : "/skrivskyddad")]" }
        logger.info("Kalendrar: \(summary.joined(separator: ", "), privacy: .public)")
    }

    func createHouseMatesCalendar() {
        guard let source = preferredSource() else {
            note("Ingen källa kan ta emot nya kalendrar")
            return
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "HouseMates"
        calendar.source = source
        calendar.cgColor = UIColor.systemGreen.cgColor
        do {
            try store.saveCalendar(calendar, commit: true)
            selectedCalendarID = calendar.calendarIdentifier
            note("Skapade HouseMates i \(source.title) (\(source.sourceType.name))")
        } catch {
            note("Kunde inte skapa kalender i \(source.title): \(error.localizedDescription)")
        }
        reload()
    }

    /// iCloud first: it is the only kind of calendar the partner can be invited to from the Calendar app.
    private func preferredSource() -> EKSource? {
        store.sources.first { $0.sourceType == .calDAV && $0.title == "iCloud" }
            ?? store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .local }
    }

    func selectCalendar(titled title: String) {
        selectedCalendarID = calendars.first { $0.title == title && $0.allowsContentModifications }?.calendarIdentifier
        note(selectedCalendar.map { "Vald kalender: \($0.title) i \($0.source.title)" } ?? "Ingen skrivbar kalender heter \(title)")
    }

    /// Writes an event carrying a unique link, so the partner's app can find the shared calendar without asking.
    func writeLinkEvent() {
        guard let calendar = selectedCalendar else {
            note("Välj en kalender först")
            return
        }
        let token = UUID().uuidString.lowercased()
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = "HouseMates är kopplad"
        event.notes = "Skapad av HouseMates för att hitta er gemensamma kalender. Kan raderas."
        event.url = linkURL(for: token)
        event.isAllDay = true
        event.startDate = Calendar.current.startOfDay(for: .now)
        event.endDate = event.startDate
        do {
            try store.save(event, span: .thisEvent, commit: true)
            linkToken = token
            note("Kopplingshändelse i \(calendar.title): nyckel \(token), extern id \(event.calendarItemExternalIdentifier ?? "saknas")")
        } catch {
            note("Kunde inte skriva kopplingshändelse: \(error.localizedDescription)")
        }
    }

    /// Accepts our link token (from the event URL) or a calendarItemExternalIdentifier; empty finds any link event.
    func findCalendar(matching key: String) {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let match = eventsAroundToday(in: nil).first {
            key.isEmpty
                ? $0.url?.absoluteString.hasPrefix(linkURLPrefix) == true
                : $0.url == linkURL(for: key) || $0.calendarItemExternalIdentifier == key
        }
        guard let match else {
            note("Hittade ingen kopplingshändelse för \(key) – är kalendern delad och accepterad?")
            return
        }
        selectedCalendarID = match.calendar.calendarIdentifier
        note("Hittade gemensam kalender: \(match.calendar.title) i \(match.calendar.source.title), extern id \(match.calendarItemExternalIdentifier ?? "saknas"), url \(match.url?.absoluteString ?? "saknas")")
    }

    func openCalendarApp() {
        open("calshow:\(Date.now.timeIntervalSinceReferenceDate)")
    }

    func open(_ address: String) {
        guard let url = URL(string: address) else {
            note("Ogiltig adress: \(address)")
            return
        }
        UIApplication.shared.open(url) { [weak self] opened in
            self?.note(opened ? "Öppnade \(address)" : "Kunde inte öppna \(address)")
        }
    }

    /// Timestamped event, so sync delay to the partner's phone can be read off directly.
    func writeTestEvent() {
        guard let calendar = selectedCalendar else {
            note("Välj en kalender först")
            return
        }
        let title = "Test \(Date.now.formatted(date: .omitted, time: .standard))"
        if save(title: title, start: .now.addingTimeInterval(3600), in: calendar) {
            note("Skrev \(title) i \(calendar.title)")
        }
    }

    var upcomingInSelectedCalendar: [EKEvent] {
        guard let selectedCalendar else { return [] }
        return eventsAroundToday(in: [selectedCalendar]).sorted { $0.lastModifiedDate ?? .distantPast > $1.lastModifiedDate ?? .distantPast }
    }

    /// Path D: our server owns the event; the app copies it into a calendar on the device.
    func mirrorEvent(titled title: String, inHours: Double, wokenIn state: String) -> Bool {
        let calendar = calendars.first { $0.title == "HouseMates" && $0.allowsContentModifications }
        guard let calendar else {
            note("Push i \(state): ingen skrivbar HouseMates-kalender att spegla till")
            return false
        }
        let saved = save(title: title, start: .now.addingTimeInterval(inHours * 3600), in: calendar)
        note("Push i \(state): \(saved ? "speglade" : "kunde inte spegla") \(title) till \(calendar.title)")
        return saved
    }

    private func save(title: String, start: Date, in calendar: EKCalendar) -> Bool {
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(3600)
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return true
        } catch {
            note("Kunde inte spara \(title): \(error.localizedDescription)")
            return false
        }
    }

    private func eventsAroundToday(in calendars: [EKCalendar]?) -> [EKEvent] {
        let now = Date.now
        let predicate = store.predicateForEvents(
            withStart: Calendar.current.date(byAdding: .day, value: -2, to: now)!,
            end: Calendar.current.date(byAdding: .day, value: 7, to: now)!,
            calendars: calendars
        )
        return store.events(matching: predicate)
    }

    private let linkURLPrefix = "housemates://koppling/"

    private func linkURL(for token: String) -> URL? {
        URL(string: linkURLPrefix + token)
    }

    func note(_ message: String) {
        let line = "\(Date.now.formatted(date: .omitted, time: .standard)) \(message)"
        log.append(line)
        logger.info("\(line, privacy: .public)")
    }
}

extension EKSourceType {
    var name: String {
        switch self {
        case .local: "lokal"
        case .exchange: "Exchange"
        case .calDAV: "CalDAV"
        case .mobileMe: "MobileMe"
        case .subscribed: "prenumeration"
        case .birthdays: "födelsedagar"
        @unknown default: "okänd"
        }
    }
}
