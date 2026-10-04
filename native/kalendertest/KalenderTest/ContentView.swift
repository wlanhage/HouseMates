import EventKit
import SwiftUI

struct ContentView: View {
    @State private var link = CalendarLink()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                if !link.hasAccess {
                    accessSection
                } else if let calendar = link.linkedCalendar {
                    linkedSections(calendar)
                } else if let pending = link.pendingCode {
                    waitingSections(pending)
                } else {
                    setupSections
                }
                logSection
            }
            .navigationTitle("Kalendertest")
            .refreshable { link.refresh() }
        }
        .onOpenURL { url in
            if let code = LinkCode(url: url) {
                link.link(with: code)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                link.refresh()
            }
        }
    }

    private var accessSection: some View {
        Section {
            Text("HouseMates behöver åtkomst för att visa och skapa händelser i den kalender ni väljer. Andra kalendrar används inte.")
            Button("Ge åtkomst") { Task { await link.requestAccess() } }
        }
    }

    private var setupSections: some View {
        Group {
            Section("Välj en kalender ni redan delar") {
                calendarRows { link.choose($0) }
                Button("Skapa ny HouseMates-kalender") { link.createHouseMatesCalendar() }
            }
            Section("Har din partner redan satt upp?") {
                PasteButton(payloadType: String.self) { texts in
                    guard let code = texts.lazy.compactMap(LinkCode.init(text:)).first else { return }
                    Task { @MainActor in link.link(with: code) }
                }
            }
        }
    }

    private func waitingSections(_ code: LinkCode) -> some View {
        Group {
            Section("Väntar på inbjudan") {
                Text("Öppna inbjudan till \(code.calendarTitle) (notis eller Kalender → Inkorg) och tryck Gå med. Appen hittar kalendern själv när du kommer tillbaka.")
                Button("Försök igen") { link.refresh() }
            }
            Section("Eller välj kalendern själv") {
                calendarRows { link.pickManually($0) }
            }
        }
    }

    private func linkedSections(_ calendar: EKCalendar) -> some View {
        Group {
            Section("Er kalender") {
                LabeledContent(calendar.title, value: calendar.source.title)
                Button("Skriv testhändelse") { link.writeTestEvent() }
            }
            if let code = link.shareCode {
                Section("Skicka till din partner") {
                    ShareLink("Skicka kopplingskod", item: code.shareText)
                    ShareGuide(calendarTitle: calendar.title)
                }
            }
            Section("Senast ändrat") {
                ForEach(link.recentEvents) { event in
                    VStack(alignment: .leading) {
                        Text(event.title)
                        Text("ändrad \(time(event.changedAt)) · syntes här \(time(event.seenAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button("Koppla från", role: .destructive) { link.unlink() }
            }
        }
    }

    private var logSection: some View {
        Section("Logg") {
            ForEach(Array(link.log.enumerated()), id: \.offset) { entry in
                Text(entry.element).font(.caption)
            }
        }
    }

    private func calendarRows(action: @escaping (EKCalendar) -> Void) -> some View {
        ForEach(link.choosableCalendars, id: \.calendarIdentifier) { calendar in
            Button { action(calendar) } label: {
                LabeledContent(calendar.title, value: calendar.source.title)
            }
        }
    }

    private func time(_ date: Date?) -> String {
        date?.formatted(date: .omitted, time: .standard) ?? "–"
    }
}

private struct ShareGuide: View {
    let calendarTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Om kalendern inte redan är delad med din partner:").bold()
            Text("1. Öppna Kalender-appen och tryck Kalendrar.")
            Text("2. Tryck ⓘ vid \(calendarTitle).")
            Text("3. Tryck Lägg till person, välj din partner och tryck Lägg till.")
        }
        .font(.subheadline)
    }
}
