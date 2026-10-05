import EventKit
import EventKitUI
import SwiftUI

struct CalendarView: View {
    @Environment(AppSession.self) private var session
    let calendar: SharedCalendar
    @State private var editing: EditRequest?
    @State private var isChoosing = false
    @AppStorage("visa-delningsguide") private var showsShareGuide = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Kalender")
                .toolbar {
                    if calendar.state == .linked && !isChoosing {
                        Menu {
                            Button("Byt kalender") { isChoosing = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        Button {
                            if let event = calendar.newEvent() { editing = EditRequest(event: event, isNew: true) }
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .sheet(item: $editing) { request in
                    EventEditor(store: calendar.store, event: request.event) { action in finish(request, action) }
                        .ignoresSafeArea()
                }
                .alert("Kalendern", isPresented: errorIsShown) {
                    Button("OK") {}
                } message: {
                    Text(calendar.errorMessage ?? "")
                }
        }
    }

    private var partnerName: String { session.partner?.name ?? "din partner" }

    @ViewBuilder
    private var content: some View {
        switch calendar.state {
        case .needsAccess:
            accessExplanation
        case .needsSetup:
            chooser
        case .waitingForInvite:
            waiting
        case .linked:
            if isChoosing { chooser } else { events }
        }
    }

    /// Visas före systemdialogen. Knappen heter "Fortsätt" enligt App Review (riktlinje 5.1.1(iv)).
    private var accessExplanation: some View {
        ContentUnavailableView {
            Label("Er gemensamma kalender", systemImage: "calendar")
        } description: {
            Text("HouseMates visar kalendern du och \(partnerName) delar och lägger in händelser i den. Andra kalendrar används inte.")
        } actions: {
            Button("Fortsätt") { Task { await calendar.requestAccess() } }
                .buttonStyle(.borderedProminent)
        }
    }

    private var chooser: some View {
        List {
            Section {
                Text("Välj en kalender ni redan delar, eller skapa en ny som du sedan delar med \(partnerName).")
            }
            Section("Dina kalendrar") {
                ForEach(calendar.choosableCalendars, id: \.calendarIdentifier) { candidate in
                    Button { Task { await choose(candidate) } } label: {
                        LabeledContent(candidate.title, value: candidate.source.title)
                    }
                }
            }
            Section {
                Button("Skapa ny HouseMates-kalender") {
                    if let created = calendar.createHouseMatesCalendar() { Task { await choose(created) } }
                }
                if isChoosing {
                    Button("Avbryt", role: .cancel) { isChoosing = false }
                }
            }
        }
    }

    private var waiting: some View {
        List {
            Section("Väntar på kalendern") {
                Text("\(partnerName) har valt kalendern \(session.household?.calendarTitle ?? ""). Öppna inbjudan (notis eller Kalender → Inkorg) och tryck Gå med. Appen hittar kalendern själv när du kommer tillbaka.")
                Button("Försök igen") { calendar.refresh() }
            }
            Section("Eller välj kalendern själv") {
                ForEach(calendar.choosableCalendars, id: \.calendarIdentifier) { candidate in
                    Button { calendar.pickManually(candidate) } label: {
                        LabeledContent(candidate.title, value: candidate.source.title)
                    }
                }
            }
        }
    }

    private var events: some View {
        List {
            if showsShareGuide, let title = calendar.linkedCalendar?.title {
                ShareGuide(calendarTitle: title, partnerName: partnerName) { showsShareGuide = false }
            }
            if calendar.upcoming.isEmpty {
                Text("Inga händelser de kommande 60 dagarna.").foregroundStyle(.secondary)
            }
            ForEach(calendar.upcoming) { day in
                Section(dayTitle(day.day)) {
                    ForEach(day.events, id: \.self) { event in
                        Button { editing = EditRequest(event: event, isNew: false) } label: {
                            EventRow(event: event)
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
        .refreshable { calendar.refresh() }
    }

    private var errorIsShown: Binding<Bool> {
        Binding(get: { calendar.errorMessage != nil }, set: { if !$0 { calendar.errorMessage = nil } })
    }

    private func choose(_ chosen: EKCalendar) async {
        guard let uids = calendar.link(to: chosen) else { return }
        do {
            try await session.saveCalendarLink(title: chosen.title, eventUIDs: uids)
            showsShareGuide = true
            isChoosing = false
        } catch {
            calendar.errorMessage = userMessage(for: error)
        }
    }

    private func finish(_ request: EditRequest, _ action: EKEventEditViewAction) {
        editing = nil
        if let activity = calendar.activity(after: action, on: request.event, wasNew: request.isNew) {
            Task { await session.logCalendarActivity(activity) }
        }
        calendar.refresh()
    }

    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Idag" }
        if Calendar.current.isDateInTomorrow(day) { return "Imorgon" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

private struct EditRequest: Identifiable {
    let id = UUID()
    let event: EKEvent
    let isNew: Bool
}

private struct EventRow: View {
    let event: EKEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(timeLabel)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            VStack(alignment: .leading) {
                Text(event.title ?? "")
                if let location = event.location, !location.isEmpty {
                    Text(location).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var timeLabel: String {
        if event.isAllDay { return "Heldag" }
        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start)–\(end)"
    }
}

private struct ShareGuide: View {
    let calendarTitle: String
    let partnerName: String
    let done: () -> Void

    var body: some View {
        Section("Dela med \(partnerName)") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Om kalendern inte redan är delad:")
                Text("1. Öppna Kalender-appen och tryck Kalendrar.")
                Text("2. Tryck ⓘ vid \(calendarTitle).")
                Text("3. Tryck Lägg till person, välj \(partnerName) och tryck Lägg till.")
            }
            .font(.subheadline)
            Button("Klart", action: done)
        }
    }
}

/// Apples egen redigeringsvy: återkommande händelser, larm och plats ingår utan egen kod.
struct EventEditor: UIViewControllerRepresentable {
    let store: EKEventStore
    let event: EKEvent
    let onFinish: (EKEventEditViewAction) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onFinish: (EKEventEditViewAction) -> Void

        init(onFinish: @escaping (EKEventEditViewAction) -> Void) {
            self.onFinish = onFinish
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onFinish(action)
        }
    }
}
