import EventKit
import EventKitUI
import SwiftUI

struct CalendarView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.openURL) private var openURL
    let calendar: SharedCalendar
    let assignees: EventAssigneeList
    let chores: ChoreList
    @State private var editing: EditRequest?
    @State private var editingChore: Chore?
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
                        .accessibilityLabel("Fler val")
                        Button {
                            if let event = calendar.newEvent() { editing = EditRequest(event: event, isNew: true) }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Ny händelse")
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
                    Text(calendar.errorMessage ?? assignees.errorMessage ?? "")
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
                MonthSections(calendar: calendar, assignees: assignees, chores: chores, edit: edit, editChore: { editingChore = $0 })
            } else {
                let days = listDays
                if days.isEmpty {
                    Text("Inga händelser de kommande 60 dagarna.").foregroundStyle(.secondary)
                }
                ForEach(days) { day in
                    Section(dayTitle(day.id)) {
                        ForEach(day.events, id: \.self) { event in
                            EventButton(event: event, assignees: assignees, edit: edit)
                        }
                        ForEach(day.chores) { chore in
                            ChoreRow(chore: chore, markDone: { chores.markDone(chore, by: session.me?.id) }, edit: { editingChore = chore })
                        }
                    }
                }
            }
        }
        .refreshable {
            calendar.refresh()
            await assignees.sync()
            await chores.sync()
        }
        .undoBanner(for: chores)
        .sheet(item: $editingChore) { chore in
            ChoreEditor(chores: chores, chore: chore)
        }
    }

    /// Händelser och städsysslor dag för dag de kommande 60 dagarna. Försenade sysslor visas på
    /// idag, som i webbappen.
    private var listDays: [ListDay] {
        let today = LocalDay.string(from: .now)
        let lastDay = LocalDay.adding(59, to: today) ?? today
        var days: [String: ListDay] = [:]
        for eventDay in calendar.upcoming {
            let day = LocalDay.string(from: eventDay.day)
            days[day, default: ListDay(id: day)].events = eventDay.events
        }
        for (day, dueChores) in ChoreSchedule.byDueDay(chores.sorted, overdueOn: today) where day <= lastDay {
            days[day, default: ListDay(id: day)].chores = dueChores
        }
        return days.values.sorted { $0.id < $1.id }
    }

    private func edit(_ event: EKEvent) {
        editing = EditRequest(event: event, isNew: false)
    }

    private var askingIsShown: Binding<Bool> {
        Binding(get: { askingAssignee != nil }, set: { if !$0 { askingAssignee = nil } })
    }

    private var errorIsShown: Binding<Bool> {
        Binding(
            get: { calendar.errorMessage != nil || assignees.errorMessage != nil },
            set: { if !$0 { calendar.errorMessage = nil; assignees.errorMessage = nil } }
        )
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
            } else if activity.type == "event.deleted" && !request.event.hasRecurrenceRules {
                // Av en återkommande händelse kan bara ett tillfälle ha raderats; resten är kvar.
                assignees.forget(activity.eventUID)
            }
        }
        calendar.refresh()
    }

    private func dayTitle(_ day: String) -> String {
        guard let date = LocalDay.date(from: day) else { return day }
        if Calendar.current.isDateInToday(date) { return "Idag" }
        if Calendar.current.isDateInTomorrow(date) { return "Imorgon" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

/// En dag i listan ("2026-10-07").
private struct ListDay: Identifiable {
    let id: String
    var events: [EKEvent] = []
    var chores: [Chore] = []
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
            EventRow(event: event, assignee: assignee)
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

/// Titeln överst; tid, person och plats på raden under, så att inget behöver en fast bredd
/// (12-timmarsklocka och större text får plats) och personen syns med namn, inte bara färg.
private struct EventRow: View {
    let event: EKEvent
    let assignee: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.title ?? "")
            HStack(spacing: 6) {
                Text(timeLabel).monospacedDigit()
                Text("·")
                PersonLabel(assignee: assignee)
                if let location = event.location, !location.isEmpty {
                    Text("·")
                    Text(location).lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeLabel: String {
        if event.isAllDay { return "Heldag" }
        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start)–\(end)"
    }
}

/// Månadsvyn: ett rutnät med en prick per händelse och en ring per städsyssla i personens färg, och
/// den valda dagens händelser och sysslor.
private struct MonthSections: View {
    @Environment(AppSession.self) private var session
    let calendar: SharedCalendar
    let assignees: EventAssigneeList
    let chores: ChoreList
    let edit: (EKEvent) -> Void
    let editChore: (Chore) -> Void
    @State private var month = MonthGrid(containing: LocalDay.string(from: .now))
    @State private var selectedDay = LocalDay.string(from: .now)

    var body: some View {
        let today = LocalDay.string(from: .now)
        let days = calendar.eventsByDay(from: month.first, through: month.last)
        let choreDays = ChoreSchedule.byDueDay(chores.sorted)
        Section {
            VStack(spacing: 12) {
                HStack {
                    Button { show(month.adding(months: -1)) } label: { MonthArrow(systemName: "chevron.left") }
                        .accessibilityLabel("Föregående månad")
                    Spacer()
                    Text(month.title).font(.headline)
                    Spacer()
                    Button { show(month.adding(months: 1)) } label: { MonthArrow(systemName: "chevron.right") }
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
                                        colors: dotColors(days[day] ?? []),
                                        rings: ringColors(choreDays[day] ?? [])
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
            let dueChores = choreDays[selectedDay] ?? []
            if events.isEmpty && dueChores.isEmpty {
                Text("Inget inplanerat.").foregroundStyle(.secondary)
            }
            ForEach(events, id: \.self) { event in
                EventButton(event: event, assignees: assignees, edit: edit)
            }
            ForEach(dueChores) { chore in
                ChoreRow(chore: chore, markDone: { chores.markDone(chore, by: session.me?.id) }, edit: { editChore(chore) })
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

    /// En ring per person som har städ den dagen, högst två, som i webbappen.
    private func ringColors(_ chores: [Chore]) -> [Color] {
        var assignees: [UUID?] = []
        for chore in chores where !assignees.contains(chore.assignee) {
            assignees.append(chore.assignee)
        }
        return assignees.prefix(2).map { session.color(for: $0) }
    }
}

private struct DayCell: View {
    let day: String
    let isToday: Bool
    let isSelected: Bool
    let colors: [Color]
    let rings: [Color]

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
                ForEach(Array(rings.enumerated()), id: \.offset) { _, color in
                    Circle().strokeBorder(color, lineWidth: 1.5).frame(width: 6, height: 6)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LocalDay.label(day))
        .accessibilityValue([colors.isEmpty ? nil : "Har händelser", rings.isEmpty ? nil : "Har städ"].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Pilen för att byta månad, med en träffyta stor nog för ett finger.
private struct MonthArrow: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
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
