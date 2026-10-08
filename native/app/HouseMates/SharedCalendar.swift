import EventKit
import EventKitUI
import Observation
import UIKit

struct EventDay: Identifiable {
    let day: Date
    let events: [EKEvent]
    var id: Date { day }
}

/// Händelse i kalendern som partnern ska få en notis om (läses av log_calendar_activity).
struct CalendarActivity: Equatable {
    let type: String
    let eventUID: String
    let title: String
    let start: String
}

/// Kopplar telefonen till den kalender hushållet delar (native/README.md, väg A). Bara den
/// kalendern läses och skrivs. Vilken kalender det är sparas i hushållet på servern som titel
/// och UID för några händelser i den, så att partnerns telefon hittar samma kalender själv.
@MainActor
@Observable
final class SharedCalendar {
    enum State: Equatable {
        case needsAccess
        case accessDenied
        case needsSetup
        case waitingForInvite
        case linked
    }

    private(set) var state: State = .needsAccess
    private(set) var linkedCalendar: EKCalendar?
    private(set) var choosableCalendars: [EKCalendar] = []
    private(set) var upcoming: [EventDay] = []
    /// Nya UID:n för hushållet när de sparade inte längre finns i kalendern (se `replacementUIDs`).
    private(set) var uidsToSave: [String]?
    var errorMessage: String?

    /// Skapas först när den behövs: SwiftUI skapar objektet på nytt varje gång vyn byggs om, men
    /// behåller bara det första.
    @ObservationIgnored lazy var store = EKEventStore()
    private let defaults = UserDefaults.standard
    @ObservationIgnored private var household: Household?
    @ObservationIgnored private var storeChanges: NSObjectProtocol?

    private static let linkedCalendarKey = "kopplad-kalender"
    private static let linkedUIDsKey = "kopplad-med-uids"
    static let markerURL = URL(string: "housemates://koppling")!

    func update(household: Household?) {
        self.household = household
        observeStoreChanges()
        refresh()
    }

    /// Kalendern läses om när den ändras utanför appen, t.ex. i Apple Kalender eller via iCloud.
    private func observeStoreChanges() {
        guard storeChanges == nil else { return }
        storeChanges = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func requestAccess() async {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            errorMessage = "Kunde inte be om åtkomst till kalendern."
        }
        refresh()
    }

    func refresh() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            break
        case .notDetermined:
            state = .needsAccess
            return
        default:
            // Nekad, begränsad eller "bara lägga till": iOS frågar inte igen, så det går bara att ändra i Inställningar.
            state = .accessDenied
            return
        }
        choosableCalendars = store.calendars(for: .event)
            .filter { $0.allowsContentModifications && !$0.isSubscribed && $0.type != .birthday }
            .sorted { ($0.isICloud ? 0 : 1, $0.title) < ($1.isICloud ? 0 : 1, $1.title) }
        linkedCalendar = locateHouseholdCalendar()
        upcoming = linkedCalendar.map(eventDays(in:)) ?? []
        uidsToSave = linkedCalendar.flatMap(replacementUIDs(for:))
        if linkedCalendar != nil {
            state = .linked
        } else if household?.calendarEventUIDs.isEmpty ?? true {
            state = .needsSetup
        } else {
            state = .waitingForInvite
        }
    }

    // MARK: Den som sätter upp

    /// En befintlig kalender känns igen på händelser som redan finns i den, så inget skrivs till den.
    /// En tom kalender får en kopplingshändelse som partnerns telefon raderar när den hittat kalendern.
    /// Svaret är det som ska sparas i hushållet.
    func link(to calendar: EKCalendar) -> [String]? {
        let existing = upcomingEventUIDs(in: calendar)
        guard let uids = existing.isEmpty ? markerUID(in: calendar).map({ [$0] }) : existing else { return nil }
        remember(calendar, uids: uids)
        refresh()
        return uids
    }

    func createHouseMatesCalendar() -> EKCalendar? {
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "HouseMates"
        calendar.cgColor = UIColor.systemGreen.cgColor
        calendar.source = store.sources.first(where: \.isICloud) ?? store.defaultCalendarForNewEvents?.source
        do {
            try store.saveCalendar(calendar, commit: true)
            return calendar
        } catch {
            errorMessage = "Kunde inte skapa kalendern. Kontrollera att iCloud är påslaget för Kalender i telefonens inställningar."
            return nil
        }
    }

    // MARK: Partnern

    /// Om den automatiska kopplingen inte hittar kalendern kan partnern välja själv; då varnar vi
    /// om kalendern inte innehåller hushållets händelser.
    func pickManually(_ calendar: EKCalendar) {
        let uids = household?.calendarEventUIDs ?? []
        let isSame = calendar.title == household?.calendarTitle || uids.contains { uid in
            store.calendarItems(withExternalIdentifier: uid).contains { $0.calendar?.calendarIdentifier == calendar.calendarIdentifier }
        }
        if !isSame {
            errorMessage = "\(calendar.title) innehåller inga av hushållets händelser och är troligen fel kalender. Har du accepterat inbjudan?"
        }
        remember(calendar, uids: uids)
        refresh()
    }

    // MARK: Händelser

    func newEvent() -> EKEvent? {
        guard let linkedCalendar else { return nil }
        let event = EKEvent(eventStore: store)
        event.calendar = linkedCalendar
        let nextHour = Calendar.current.nextDate(after: .now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? .now
        event.startDate = nextHour
        event.endDate = nextHour.addingTimeInterval(3600)
        return event
    }

    /// Bara ändringar i den delade kalendern berättas för partnern (man kan flytta en händelse
    /// till en egen kalender i Apples redigeringsvy).
    func activity(after action: EKEventEditViewAction, on event: EKEvent, wasNew: Bool) -> CalendarActivity? {
        guard event.calendar?.calendarIdentifier == linkedCalendar?.calendarIdentifier,
              let uid = event.calendarItemExternalIdentifier else { return nil }
        let type: String
        switch action {
        case .saved: type = wasNew ? "event.created" : "event.updated"
        case .deleted: type = "event.deleted"
        default: return nil
        }
        return CalendarActivity(type: type, eventUID: uid, title: event.title ?? "", start: Self.activityStart(for: event))
    }

    /// Heldag som datum, annars ISO-tid – det format digest.ts förstår.
    nonisolated static func activityStart(for event: EKEvent) -> String {
        if event.isAllDay {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: event.startDate)
        }
        return ISO8601DateFormatter().string(from: event.startDate)
    }

    /// Den delade kalenderns händelser dag för dag ("2026-10-07") mellan två dagar, för månadsvyn
    /// och Hem.
    func eventsByDay(from first: String, through last: String) -> [String: [EKEvent]] {
        guard let linkedCalendar, let start = LocalDay.date(from: first),
              let end = LocalDay.adding(1, to: last).flatMap(LocalDay.date(from:)) else { return [:] }
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: [linkedCalendar]))
            .filter { $0.url != Self.markerURL }
        return Self.byDay(events, from: first, through: last)
    }

    /// En händelse som pågår flera dagar finns på varje dag. Sluttiden räknas inte med, så en
    /// händelse som slutar vid midnatt hamnar inte på dagen efter. Heldag först, sedan efter tid.
    nonisolated static func byDay(_ events: [EKEvent], from first: String, through last: String) -> [String: [EKEvent]] {
        var days: [String: [EKEvent]] = [:]
        for event in events {
            let lastMoment = max(event.startDate, event.endDate.addingTimeInterval(-1))
            var day = max(LocalDay.string(from: event.startDate), first)
            let lastDay = min(LocalDay.string(from: lastMoment), last)
            while day <= lastDay {
                days[day, default: []].append(event)
                guard let next = LocalDay.adding(1, to: day) else { break }
                day = next
            }
        }
        return days.mapValues { events in
            events.sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
        }
    }

    /// Händelser som började före idag (flerdagars) visas på idag.
    nonisolated static func groupByDay(_ events: [EKEvent], from today: Date) -> [EventDay] {
        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: today)
        return Dictionary(grouping: events) { max(calendar.startOfDay(for: $0.startDate), firstDay) }
            .map { EventDay(day: $0.key, events: $0.value.sorted { $0.startDate < $1.startDate }) }
            .sorted { $0.day < $1.day }
    }

    // MARK: Privat

    /// Den lokala kopplingen gäller så länge hushållet pekar på samma kalender; annars letas den upp
    /// via UID:n. En kalender som hittas sparas på telefonen, och kopplingshändelsen raderas.
    private func locateHouseholdCalendar() -> EKCalendar? {
        let uids = household?.calendarEventUIDs ?? []
        if let id = defaults.string(forKey: Self.linkedCalendarKey),
           let calendar = store.calendar(withIdentifier: id),
           defaults.stringArray(forKey: Self.linkedUIDsKey) == uids {
            return calendar
        }
        guard !uids.isEmpty, let calendar = calendarContaining(uids) else { return nil }
        remember(calendar, uids: uids)
        removeMarkers(listedIn: uids)
        return calendar
    }

    /// Flera träffar kan peka på olika kalendrar (t.ex. en inbjudan kopierad till en egen kalender);
    /// kalendern med flest av hushållets händelser vinner.
    private func calendarContaining(_ uids: [String]) -> EKCalendar? {
        let calendars = uids.flatMap { store.calendarItems(withExternalIdentifier: $0) }.compactMap(\.calendar)
        return Dictionary(grouping: calendars, by: \.calendarIdentifier).values.max { $0.count < $1.count }?.first
    }

    /// Hushållets UID:n ska peka på händelser som finns, så att en telefon som installerat om appen
    /// hittar kalendern. Kopplingshändelsen raderas när partnern hittat kalendern; när ingen av
    /// UID:na finns kvar föreslås nya från kalenderns kommande händelser.
    private func replacementUIDs(for calendar: EKCalendar) -> [String]? {
        let uids = household?.calendarEventUIDs ?? []
        let stillThere = uids.contains { uid in
            store.calendarItems(withExternalIdentifier: uid).contains { $0.calendar?.calendarIdentifier == calendar.calendarIdentifier }
        }
        guard !stillThere else { return nil }
        let fresh = upcomingEventUIDs(in: calendar)
        return fresh.isEmpty ? nil : fresh
    }

    /// Kommande händelser: telefoner synkar ungefär en månads historik som standard, men alltid framtiden.
    private func upcomingEventUIDs(in calendar: EKCalendar) -> [String] {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let end = Calendar.current.date(byAdding: .year, value: 1, to: .now)!
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: [calendar]))
        var seen = Set<String>()
        return Array(events.compactMap(\.calendarItemExternalIdentifier).filter { seen.insert($0).inserted }.prefix(5))
    }

    private func markerUID(in calendar: EKCalendar) -> String? {
        let marker = EKEvent(eventStore: store)
        marker.calendar = calendar
        marker.title = "HouseMates är kopplad"
        marker.isAllDay = true
        marker.startDate = Calendar.current.startOfDay(for: .now)
        marker.endDate = marker.startDate
        marker.url = Self.markerURL
        marker.notes = "Skapad av HouseMates så att din partners telefon hittar kalendern. Raderas automatiskt."
        do {
            try store.save(marker, span: .thisEvent, commit: true)
            return marker.calendarItemExternalIdentifier
        } catch {
            errorMessage = "Kunde inte förbereda kalendern. Försök igen."
            return nil
        }
    }

    private func removeMarkers(listedIn uids: [String]) {
        let markers = uids.flatMap { store.calendarItems(withExternalIdentifier: $0) }
            .compactMap { $0 as? EKEvent }
            .filter { $0.url == Self.markerURL }
        for marker in markers {
            try? store.remove(marker, span: .thisEvent, commit: true)
        }
    }

    private func eventDays(in calendar: EKCalendar) -> [EventDay] {
        let today = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 60, to: today)!
        let events = store.events(matching: store.predicateForEvents(withStart: today, end: end, calendars: [calendar]))
            .filter { $0.url != Self.markerURL }
        return Self.groupByDay(events, from: today)
    }

    private func remember(_ calendar: EKCalendar, uids: [String]) {
        defaults.set(calendar.calendarIdentifier, forKey: Self.linkedCalendarKey)
        defaults.set(uids, forKey: Self.linkedUIDsKey)
    }
}

extension EKCalendar {
    var isICloud: Bool { source?.isICloud == true }
}

private extension EKSource {
    var isICloud: Bool { sourceType == .calDAV && title == "iCloud" }
}
