import EventKit
import EventKitUI
import SwiftUI

struct CalendarView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.openURL) private var openURL
    let calendar: SharedCalendar
    let assignees: EventAssigneeList
    @State private var editing: EditRequest?
    @State private var isChoosing = false
    @State private var askingAssignee: AssigneeQuestion?
    @AppStorage("kalender-manadsvy") private var showsMonth = false
    /// Hushållet vars kalender den här telefonen just valt; guiden gäller bara den som valde.
    @AppStorage("delningsguide-hushall") private var shareGuideHousehold = ""

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
                .confirmationDialog(
                    askingAssignee.map { "För vem är \($0.title)?" } ?? "",
                    isPresented: askingIsShown,
                    titleVisibility: .visible,
                    presenting: askingAssignee
                ) { question in
                    ForEach(session.assigneeChoices) { choice in
                        Button(choice.name) { assignees.assign(question.eventUID, to: choice.id) }
                    }
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
        case .accessDenied:
            accessDenied
        case .needsSetup:
            chooser
        case .waitingForInvite:
            if isChoosing { chooser } else { waiting }
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

    private var accessDenied: some View {
        ContentUnavailableView {
            Label("Ingen åtkomst till kalendern", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text("Tryck Öppna Inställningar, välj Kalendrar och sedan Fullständig åtkomst. Inköpslistan fungerar som vanligt under tiden.")
        } actions: {
            Button("Öppna Inställningar") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
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
                Text("Hushållet använder kalendern \(session.household?.calendarTitle ?? ""). Har du fått en inbjudan till den? Öppna den (notis eller Kalender → Inkorg) och tryck Gå med. Appen hittar kalendern själv när du kommer tillbaka.")
                Button("Försök igen") { calendar.refresh() }
            }
            Section("Eller välj kalendern själv") {
                ForEach(calendar.choosableCalendars, id: \.calendarIdentifier) { candidate in
                    Button { calendar.pickManually(candidate) } label: {
                        LabeledContent(candidate.title, value: candidate.source.title)
                    }
                }
            }
            Section {
                Button("Byt kalender för hushållet") { isChoosing = true }
            } footer: {
                Text("Om kalendern har raderats eller slutat delas. Kalendern du väljer används sedan av er båda.")
            }
        }
    }

    private var events: some View {
        List {
            if shareGuideHousehold == session.household?.id.uuidString, let title = calendar.linkedCalendar?.title {
                ShareGuide(calendarTitle: title, partnerName: partnerName) { shareGuideHousehold = "" }
            }
            Picker("Visa", selection: $showsMonth) {
                Text("Lista").tag(false)
                Text("Månad").tag(true)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if showsMonth {
                MonthSections(calendar: calendar, assignees: assignees, edit: edit)
            } else {
                if calendar.upcoming.isEmpty {
                    Text("Inga händelser de kommande 60 dagarna.").foregroundStyle(.secondary)
                }
                ForEach(calendar.upcoming) { day in
                    Section(dayTitle(day.day)) {
                        ForEach(day.events, id: \.self) { event in
                            EventButton(event: event, assignees: assignees, edit: edit)
                        }
                    }
                }
            }
        }
        .refreshable { calendar.refresh() }
    }

    private func edit(_ event: EKEvent) {
        editing = EditRequest(event: event, isNew: false)
    }

    private var askingIsShown: Binding<Bool> {
        Binding(get: { askingAssignee != nil }, set: { if !$0 { askingAssignee = nil } })
    }

    private var errorIsShown: Binding<Bool> {
        Binding(get: { calendar.errorMessage != nil }, set: { if !$0 { calendar.errorMessage = nil } })
    }

    private func choose(_ chosen: EKCalendar) async {
        guard let uids = calendar.link(to: chosen) else { return }
        do {
            try await session.saveCalendarLink(title: chosen.title, eventUIDs: uids)
            shareGuideHousehold = session.household?.id.uuidString ?? ""
            isChoosing = false
        } catch {
            calendar.errorMessage = userMessage(for: error)
        }
    }

    private func finish(_ request: EditRequest, _ action: EKEventEditViewAction) {
        editing = nil
        if let activity = calendar.activity(after: action, on: request.event, wasNew: request.isNew) {
            Task { await session.logCalendarActivity(activity) }
            if activity.type == "event.created" && session.partner != nil {
                askingAssignee = AssigneeQuestion(eventUID: activity.eventUID, title: activity.title)
            } else if activity.type == "event.deleted" {
                assignees.forget(activity.eventUID)
            }
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

/// Frågan "För vem?" efter en ny händelse.
private struct AssigneeQuestion {
    let eventUID: String
    let title: String
}

/// En händelse i listan: tryck för att ändra den, håll inne för att välja vem den är för.
private struct EventButton: View {
    @Environment(AppSession.self) private var session
    let event: EKEvent
    let assignees: EventAssigneeList
    let edit: (EKEvent) -> Void

    var body: some View {
        let assignee = assignees.assignee(for: event.calendarItemExternalIdentifier)
        Button { edit(event) } label: {
            EventRow(event: event, color: session.color(for: assignee))
        }
        .foregroundStyle(.primary)
        .contextMenu {
            if let uid = event.calendarItemExternalIdentifier {
                Section("För vem?") {
                    ForEach(session.assigneeChoices) { choice in
                        Button {
                            assignees.assign(uid, to: choice.id)
                        } label: {
                            if choice.id == assignee {
                                Label(choice.name, systemImage: "checkmark")
                            } else {
                                Text(choice.name)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct EventRow: View {
    let event: EKEvent
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(timeLabel)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            VStack(alignment: .leading) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                    Text(event.title ?? "")
                }
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

/// Månadsvyn: ett rutnät med en prick per händelse i personens färg, och den valda dagens händelser.
private struct MonthSections: View {
    @Environment(AppSession.self) private var session
    let calendar: SharedCalendar
    let assignees: EventAssigneeList
    let edit: (EKEvent) -> Void
    @State private var month = MonthGrid(containing: LocalDay.string(from: .now))
    @State private var selectedDay = LocalDay.string(from: .now)

    var body: some View {
        let today = LocalDay.string(from: .now)
        let days = calendar.eventsByDay(from: month.first, through: month.last)
        Section {
            VStack(spacing: 12) {
                HStack {
                    Button { show(month.adding(months: -1)) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Föregående månad")
                    Spacer()
                    Text(month.title).font(.headline)
                    Spacer()
                    Button { show(month.adding(months: 1)) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Nästa månad")
                }
                .buttonStyle(.borderless)
                // Fasta rader i stället för LazyVGrid, som inne i en listrad gav en layoutloop.
                VStack(spacing: 4) {
                    HStack(spacing: 0) {
                        ForEach(MonthGrid.weekdays, id: \.self) { weekday in
                            Text(weekday)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(Array(month.weeks.enumerated()), id: \.offset) { _, week in
                        HStack(spacing: 0) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                if let day {
                                    DayCell(
                                        day: day,
                                        isToday: day == today,
                                        isSelected: day == selectedDay,
                                        colors: dotColors(days[day] ?? [])
                                    )
                                    .onTapGesture { selectedDay = day }
                                } else {
                                    Color.clear.frame(maxWidth: .infinity, minHeight: 44)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        Section(LocalDay.label(selectedDay)) {
            let events = days[selectedDay] ?? []
            if events.isEmpty {
                Text("Inget inplanerat.").foregroundStyle(.secondary)
            }
            ForEach(events, id: \.self) { event in
                EventButton(event: event, assignees: assignees, edit: edit)
            }
        }
    }

    private func show(_ next: MonthGrid) {
        month = next
        let today = LocalDay.string(from: .now)
        selectedDay = next.contains(today) ? today : next.first
    }

    /// En prick per händelse i personens färg, högst tre.
    private func dotColors(_ events: [EKEvent]) -> [Color] {
        events.prefix(3).map { session.color(for: assignees.assignee(for: $0.calendarItemExternalIdentifier)) }
    }
}

private struct DayCell: View {
    let day: String
    let isToday: Bool
    let isSelected: Bool
    let colors: [Color]

    var body: some View {
        VStack(spacing: 3) {
            Text(String(Int(day.suffix(2)) ?? 0))
                .font(.callout)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isSelected ? Color.white : isToday ? Color.accentColor : Color.primary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(isSelected ? Color.accentColor : Color.clear))
            HStack(spacing: 2) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                    Circle().fill(color).frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LocalDay.label(day))
        .accessibilityValue(colors.isEmpty ? "" : "Har händelser")
        .accessibilityAddTraits(.isButton)
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
