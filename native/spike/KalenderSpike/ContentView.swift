import EventKit
import SwiftUI

struct ContentView: View {
    let lab: CalendarLab
    @State private var keyToFind = ""
    @State private var feedAddress = "webcal://localhost:8787/feed.ics"
    @State private var profileAddress = "http://localhost:8787/profile.mobileconfig"

    var body: some View {
        NavigationStack {
            List {
                Section("Behörighet") {
                    if lab.hasAccess {
                        Label("Fullständig åtkomst", systemImage: "checkmark.circle")
                    } else {
                        Button("Ge kalenderåtkomst") { Task { await lab.requestAccess() } }
                    }
                }
                Section("Kalendrar") {
                    ForEach(lab.calendars, id: \.calendarIdentifier) { calendar in
                        Button { lab.selectedCalendarID = calendar.calendarIdentifier } label: {
                            CalendarRow(calendar: calendar, isSelected: calendar.calendarIdentifier == lab.selectedCalendarID)
                        }
                    }
                }
                Section("A · iCloud-delning") {
                    Button("Skapa HouseMates-kalender") { lab.createHouseMatesCalendar() }
                    Button("Skriv kopplingshändelse i vald kalender") { lab.writeLinkEvent() }
                    if let token = lab.linkToken {
                        Text(token).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    Button("Skriv testhändelse i vald kalender") { lab.writeTestEvent() }
                    TextField("Nyckel eller extern id (tomt = valfri)", text: $keyToFind)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Hitta kalender via kopplingshändelse") { lab.findCalendar(matching: keyToFind) }
                    Button("Öppna Kalender-appen") { lab.openCalendarApp() }
                }
                Section("Senast ändrat i vald kalender") {
                    ForEach(lab.upcomingInSelectedCalendar.prefix(5), id: \.calendarItemIdentifier) { event in
                        LabeledContent(event.title, value: event.lastModifiedDate?.formatted(date: .omitted, time: .standard) ?? "–")
                    }
                }
                Section("B · Prenumeration (webcal)") {
                    TextField("Adress", text: $feedAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Prenumerera") { lab.open(feedAddress) }
                }
                Section("C · CalDAV-konto via profil") {
                    TextField("Adress", text: $profileAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Installera profil") { lab.open(profileAddress) }
                }
                Section("Logg") {
                    ForEach(Array(lab.log.enumerated().reversed()), id: \.offset) { entry in
                        Text(entry.element).font(.caption)
                    }
                }
            }
            .navigationTitle("Kalenderspike")
            .refreshable { lab.refresh() }
            .onOpenURL(perform: runScriptedStep)
        }
    }

    /// Lets the experiments be driven from the Mac: xcrun simctl openurl <device> "kalenderspike://link".
    private func runScriptedStep(_ url: URL) {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in query.first { $0.name == name }?.value ?? "" }
        switch url.host() {
        case "create": lab.createHouseMatesCalendar()
        case "select": lab.selectCalendar(titled: value("title"))
        case "link": lab.writeLinkEvent()
        case "test": lab.writeTestEvent()
        case "find": lab.findCalendar(matching: value("key"))
        case "open": lab.open(value("url"))
        case "reload": lab.refresh()
        default: break
        }
    }
}

private struct CalendarRow: View {
    let calendar: EKCalendar
    let isSelected: Bool

    var body: some View {
        HStack {
            Circle().fill(Color(cgColor: calendar.cgColor)).frame(width: 10, height: 10)
            VStack(alignment: .leading) {
                Text(calendar.title)
                Text(details).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected { Image(systemName: "checkmark") }
        }
        .foregroundStyle(.primary)
    }

    private var details: String {
        var parts = ["\(calendar.source.title) · \(calendar.source.sourceType.name)"]
        if calendar.isSubscribed { parts.append("prenumererad") }
        if !calendar.allowsContentModifications { parts.append("skrivskyddad") }
        return parts.joined(separator: " · ")
    }
}
