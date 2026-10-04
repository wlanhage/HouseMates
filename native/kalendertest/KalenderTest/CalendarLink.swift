import EventKit
import Observation
import OSLog
import UIKit

struct RecentEvent: Identifiable {
    let id: String
    let title: String
    let changedAt: Date?
    let seenAt: Date
}

/// Links this phone to the one calendar the couple shares. No other calendar is read or written.
@MainActor
@Observable
final class CalendarLink {
    private(set) var hasAccess = false
    private(set) var choosableCalendars: [EKCalendar] = []
    private(set) var linkedCalendar: EKCalendar?
    private(set) var shareCode: LinkCode?
    private(set) var pendingCode: LinkCode?
    private(set) var recentEvents: [RecentEvent] = []
    private(set) var log: [String] = []

    private let store = EKEventStore()
    private let defaults = UserDefaults.standard
    private let logger = Logger(subsystem: "se.housemates.kalendertest", category: "koppling")
    @ObservationIgnored private var firstSeen: [String: Date] = [:]

    private static let linkedCalendarKey = "kopplad-kalender"
    private static let shareCodeKey = "kopplingskod"
    private static let pendingCodeKey = "väntande-kopplingskod"
    private static let markerURL = URL(string: "housemates://koppling")!

    init() {
        shareCode = storedCode(forKey: Self.shareCodeKey)
        pendingCode = storedCode(forKey: Self.pendingCodeKey)
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        reload()
    }

    func requestAccess() async {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            note("Kunde inte be om åtkomst: \(error.localizedDescription)")
        }
        reload()
    }

    func refresh() {
        store.refreshSourcesIfNecessary()
        reload()
    }

    // MARK: Den som sätter upp

    /// An existing calendar is identified by events already in it, so nothing is written to it.
    func choose(_ calendar: EKCalendar) {
        let uids = upcomingEventUIDs(in: calendar)
        guard let code = uids.isEmpty ? markerCode(in: calendar) : LinkCode(calendarTitle: calendar.title, eventUIDs: uids) else {
            return
        }
        linkTo(calendar)
        setShareCode(code)
        logger.info("Kopplingskod: \(code.url.absoluteString, privacy: .public)")
        note(uids.isEmpty
             ? "\(calendar.title) var tom, skrev en kopplingshändelse"
             : "Kopplingskod från \(uids.count) befintliga händelser i \(calendar.title), inget skrevs")
        if !calendar.isICloud {
            note("Obs: kalendrar i \(calendar.source.title) kan inte delas från Kalender-appen")
        }
    }

    func createHouseMatesCalendar() {
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "HouseMates"
        calendar.cgColor = UIColor.systemGreen.cgColor
        calendar.source = store.sources.first(where: \.isICloud) ?? store.defaultCalendarForNewEvents?.source
        do {
            try store.saveCalendar(calendar, commit: true)
            note("Skapade HouseMates i \(calendar.source.title)")
            choose(calendar)
        } catch {
            note("Kunde inte skapa kalendern: \(error.localizedDescription)")
        }
    }

    // MARK: Partnern

    func link(with code: LinkCode) {
        guard !connect(using: code) else { return }
        setPending(code)
        note("Hittar inte \(code.calendarTitle) än. Acceptera inbjudan i Kalender-appen, appen försöker igen själv.")
    }

    func pickManually(_ calendar: EKCalendar) {
        guard let code = pendingCode else { return }
        let matches = code.eventUIDs.filter { uid in
            store.calendarItems(withExternalIdentifier: uid).contains { $0.calendar?.calendarIdentifier == calendar.calendarIdentifier }
        }
        note(matches.isEmpty
             ? "Varning: \(calendar.title) innehåller inga av partnerns händelser, troligen fel kalender"
             : "Bekräftat: \(calendar.title) är samma kalender som partnerns")
        linkTo(calendar)
        setPending(nil)
    }

    func unlink() {
        defaults.removeObject(forKey: Self.linkedCalendarKey)
        linkedCalendar = nil
        setShareCode(nil)
        note("Kopplingen borttagen")
    }

    // MARK: Synktest

    func writeTestEvent() {
        guard let calendar = linkedCalendar else { return }
        let event = newEvent(titled: "Test \(Date.now.formatted(date: .omitted, time: .standard))", in: calendar)
        event.startDate = .now.addingTimeInterval(3600)
        event.endDate = event.startDate.addingTimeInterval(3600)
        if save(event) {
            note("Skrev \(event.title ?? "")")
        }
    }

    // MARK: Privat

    private func reload() {
        hasAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        guard hasAccess else { return }
        let calendars = store.calendars(for: .event)
        choosableCalendars = calendars
            .filter { $0.allowsContentModifications && !$0.isSubscribed && $0.type != .birthday }
            .sorted { ($0.isICloud ? 0 : 1, $0.title) < ($1.isICloud ? 0 : 1, $1.title) }
        let linkedID = defaults.string(forKey: Self.linkedCalendarKey)
        linkedCalendar = calendars.first { $0.calendarIdentifier == linkedID }
        recentEvents = linkedCalendar.map(recentEvents(in:)) ?? []
        if linkedCalendar == nil, let pendingCode {
            connect(using: pendingCode)
        }
    }

    @discardableResult
    private func connect(using code: LinkCode) -> Bool {
        guard let calendar = calendarContaining(code) else { return false }
        linkTo(calendar)
        setPending(nil)
        note("Kopplad till \(calendar.title) i \(calendar.source.title)")
        if !calendar.allowsContentModifications {
            note("Obs: kalendern är skrivskyddad för dig, be din partner tillåta redigering")
        }
        removeMarkers(listedIn: code)
        return true
    }

    /// Several matches can point at different calendars (e.g. an invite copied into a personal calendar);
    /// the calendar holding most of the partner's events wins.
    private func calendarContaining(_ code: LinkCode) -> EKCalendar? {
        let calendars = code.eventUIDs
            .flatMap { store.calendarItems(withExternalIdentifier: $0) }
            .compactMap(\.calendar)
        let byIdentifier = Dictionary(grouping: calendars, by: \.calendarIdentifier)
        return byIdentifier.values.max { $0.count < $1.count }?.first
    }

    /// Upcoming events only: phones sync about a month of history by default, but always the future.
    private func upcomingEventUIDs(in calendar: EKCalendar) -> [String] {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let end = Calendar.current.date(byAdding: .year, value: 1, to: .now)!
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: [calendar]))
        var seen = Set<String>()
        return Array(events.compactMap(\.calendarItemExternalIdentifier).filter { seen.insert($0).inserted }.prefix(5))
    }

    private func markerCode(in calendar: EKCalendar) -> LinkCode? {
        let marker = newEvent(titled: "HouseMates är kopplad", in: calendar)
        marker.isAllDay = true
        marker.startDate = Calendar.current.startOfDay(for: .now)
        marker.endDate = marker.startDate
        marker.url = Self.markerURL
        marker.notes = "Skapad av HouseMates så att din partners telefon hittar kalendern. Raderas automatiskt."
        guard save(marker), let uid = marker.calendarItemExternalIdentifier else { return nil }
        return LinkCode(calendarTitle: calendar.title, eventUIDs: [uid])
    }

    private func removeMarkers(listedIn code: LinkCode) {
        let markers = code.eventUIDs
            .flatMap { store.calendarItems(withExternalIdentifier: $0) }
            .compactMap { $0 as? EKEvent }
            .filter { $0.url == Self.markerURL }
        for marker in markers {
            do {
                try store.remove(marker, span: .thisEvent, commit: true)
                note("Raderade kopplingshändelsen")
            } catch {
                note("Kunde inte radera kopplingshändelsen: \(error.localizedDescription)")
            }
        }
    }

    private func recentEvents(in calendar: EKCalendar) -> [RecentEvent] {
        let start = Calendar.current.date(byAdding: .day, value: -2, to: .now)!
        let end = Calendar.current.date(byAdding: .month, value: 1, to: .now)!
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: [calendar]))
            .sorted { ($0.lastModifiedDate ?? .distantPast) > ($1.lastModifiedDate ?? .distantPast) }
            .prefix(6)
            .map { event in
                let seenAt = firstSeen[event.calendarItemIdentifier] ?? .now
                firstSeen[event.calendarItemIdentifier] = seenAt
                return RecentEvent(id: event.calendarItemIdentifier, title: event.title, changedAt: event.lastModifiedDate, seenAt: seenAt)
            }
    }

    private func linkTo(_ calendar: EKCalendar) {
        defaults.set(calendar.calendarIdentifier, forKey: Self.linkedCalendarKey)
        linkedCalendar = calendar
        recentEvents = recentEvents(in: calendar)
    }

    private func setShareCode(_ code: LinkCode?) {
        shareCode = code
        defaults.set(code?.url.absoluteString, forKey: Self.shareCodeKey)
    }

    private func setPending(_ code: LinkCode?) {
        pendingCode = code
        defaults.set(code?.url.absoluteString, forKey: Self.pendingCodeKey)
    }

    private func storedCode(forKey key: String) -> LinkCode? {
        defaults.string(forKey: key).flatMap(URL.init(string:)).flatMap(LinkCode.init(url:))
    }

    private func newEvent(titled title: String, in calendar: EKCalendar) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        return event
    }

    private func save(_ event: EKEvent) -> Bool {
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return true
        } catch {
            note("Kunde inte spara \(event.title ?? ""): \(error.localizedDescription)")
            return false
        }
    }

    private func note(_ message: String) {
        let line = "\(Date.now.formatted(date: .omitted, time: .standard)) \(message)"
        log.insert(line, at: 0)
        logger.info("\(line, privacy: .public)")
    }
}

private extension EKSource {
    var isICloud: Bool { sourceType == .calDAV && title == "iCloud" }
}

extension EKCalendar {
    var isICloud: Bool { source?.isICloud == true }
}
