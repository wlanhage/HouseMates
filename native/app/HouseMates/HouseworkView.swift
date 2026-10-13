import SwiftUI

/// Fliken Att göra: engångsuppgifter och återkommande städsysslor.
struct HouseworkView: View {
    @Environment(AppSession.self) private var session
    let todos: TodoList
    let chores: ChoreList
    @State private var part = Part.todos
    @State private var filter = AssigneeFilter.everyone
    @State private var editing: Editing?

    enum Part { case todos, chores }

    var body: some View {
        NavigationStack {
            List {
                PageTitle("Att göra")
                PillTabs(selection: $part, options: [(.todos, "Uppgifter"), (.chores, "Städ")])
                    .plainRow(top: 4)

                FilterPills(filter: $filter)
                    .plainRow(top: 6, bottom: 8)

                if todos.isOffline || chores.isOffline {
                    OfflineNotice(hasPending: !todos.pending.isEmpty || !chores.pending.isEmpty)
                }

                switch part {
                case .todos: TodoSections(todos: todos, filter: filter) { editing = .todo($0) }
                case .chores: ChoreSections(chores: chores, filter: filter) { editing = .chore($0) }
                }
            }
            .listStyle(.plain)
            .paperBackground()
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { AppTopBar() }
            .onChange(of: session.partner?.id) { filter = .everyone }
            .refreshable {
                await todos.sync()
                await chores.sync()
            }
            .undoBanner(for: todos)
            .undoBanner(for: chores)
            .sheet(item: $editing) { editing in
                switch editing {
                case let .todo(todo): TodoEditor(todos: todos, todo: todo)
                case let .chore(chore): ChoreEditor(chores: chores, chore: chore)
                }
            }
            .alert("Något gick fel", isPresented: errorIsShown) {
                Button("OK") {}
            } message: {
                Text(todos.errorMessage ?? chores.errorMessage ?? "")
            }
        }
    }

    private var errorIsShown: Binding<Bool> {
        Binding(
            get: { todos.errorMessage != nil || chores.errorMessage != nil },
            set: { if !$0 { todos.errorMessage = nil; chores.errorMessage = nil } }
        )
    }

    /// Det som redigeras i arket. Nya uppgifter och sysslor läggs till med plusset i flikraden.
    enum Editing: Identifiable {
        case todo(Todo)
        case chore(Chore)

        var id: UUID {
            switch self {
            case let .todo(todo): todo.id
            case let .chore(chore): chore.id
            }
        }
    }
}

/// Alla, Du eller partnern. Gemensamma uppgifter syns under Alla, som också är förvalt. Gäller öppna
/// uppgifter och städsysslor.
private struct FilterPills: View {
    @Environment(AppSession.self) private var session
    @Binding var filter: AssigneeFilter

    var body: some View {
        HStack(spacing: 8) {
            ForEach(filters, id: \.self) { option in
                let isSelected = option == filter
                Button {
                    filter = option
                } label: {
                    Text(name(for: option))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 7)
                        .foregroundStyle(isSelected ? Color.onAccent : Color.inkMuted)
                        .background(isSelected ? Color.accentColor : Color.surface, in: Capsule())
                        .overlay { Capsule().strokeBorder(isSelected ? Color.accentColor : Color.hairline) }
                        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }

    private var filters: [AssigneeFilter] {
        [.everyone] + [session.me, session.partner].compactMap { $0 }.map { .person($0.id) }
    }

    private func name(for filter: AssigneeFilter) -> String {
        switch filter {
        case .everyone: String(appLocalized: "Alla")
        case let .person(id): id == session.me?.id ? String(appLocalized: "Du") : session.name(for: id)
        }
    }
}

private extension View {
    /// Ett tryck öppnar redigeringen. Ingen knapp, eftersom en knapp utlöses också när fingret
    /// sveper över raden, som när man byter dag på Hem.
    func tapToEdit(_ edit: @escaping () -> Void) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: edit)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { edit() }
    }
}

// MARK: Uppgifter

private struct TodoSections: View {
    @Environment(AppSession.self) private var session
    let todos: TodoList
    let filter: AssigneeFilter
    let edit: (Todo) -> Void
    /// Klart är hopfällt från början, som i webbappen.
    @State private var showsFinished = false

    var body: some View {
        let open = todos.open.filter { filter.includes($0.assignee) }
        let finished = todos.finished
        if open.isEmpty {
            EmptyCard(emoji: "✅", text: filter == .everyone ? "Inga öppna uppgifter." : "Inga öppna uppgifter här.")
        }
        ForEach(open) { todo in
            TodoRow(todo: todo, toggle: { todos.toggle(todo, by: session.me?.id) }, edit: { edit(todo) })
                .cardRow()
        }
        .onDelete { offsets in todos.remove(offsets.map { open[$0] }) }
        if !finished.isEmpty {
            SectionTitle("Klart · \(finished.count)") {
                if showsFinished {
                    Button("Rensa") { todos.clearFinished() }
                        .buttonStyle(SmallButtonStyle())
                }
                Button {
                    withAnimation { showsFinished.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(showsFinished ? 90 : 0))
                        .foregroundStyle(Color.inkMuted)
                        .frame(minWidth: 44, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsFinished ? "Dölj klara" : "Visa klara")
            }
            .plainRow(top: 14, bottom: 2)
            if showsFinished {
                ForEach(finished) { todo in
                    TodoRow(todo: todo, toggle: { todos.toggle(todo, by: session.me?.id) }, edit: { edit(todo) })
                        .cardRow()
                }
                .onDelete { offsets in todos.remove(offsets.map { finished[$0] }) }
            }
        }
    }
}

struct TodoRow: View {
    let todo: Todo
    let toggle: () -> Void
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            CheckButton(
                isOn: todo.done,
                accessibilityLabel: todo.done ? Text("Markera \(todo.title) som inte klar") : Text("Markera \(todo.title) som klar"),
                action: toggle
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .strikethrough(todo.done)
                    .foregroundStyle(todo.done ? Color.inkMuted : Color.ink)
                if let notes = todo.notes {
                    Text(notes)
                        .font(.footnote)
                        .foregroundStyle(Color.inkMuted)
                        .lineLimit(1)
                }
            }
            .tapToEdit(edit)

            if let badge, !todo.done {
                badge
            }
            PersonAvatar(assignee: todo.assignee)
        }
    }

    /// "Försenad", "Idag", "Imorgon", eller "fre 10 okt–sön 12 okt" för en period.
    private var badge: DueBadge? {
        guard let due = todo.dueDate, let daysLeft = LocalDay.days(until: due) else { return nil }
        let kind = DueBadge.Kind(daysLeft: daysLeft)
        if kind == .overdue {
            return DueBadge(text: String(appLocalized: "Försenad"), kind: kind)
        }
        guard let start = todo.startDate else { return DueBadge(text: LocalDay.label(due), kind: kind) }
        return DueBadge(text: LocalDay.period(from: start, to: due), kind: kind)
    }
}

struct TodoEditor: View {
    @Environment(\.dismiss) private var dismiss
    let todos: TodoList
    let todo: Todo?

    @State private var title = ""
    @State private var notes = ""
    @State private var assignee: UUID?
    @State private var hasDueDate = false
    @State private var dueDate = Date.now
    @State private var hasStartDate = false
    @State private var startDate = Date.now
    @FocusState private var titleIsFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Vad ska göras?", text: $title)
                        .focused($titleIsFocused)
                    TextField("Anteckningar (valfritt)", text: $notes, axis: .vertical)
                        .lineLimit(1...6)
                }
                Section {
                    AssigneePicker(assignee: $assignee)
                } header: {
                    FieldLabel("Vem gör det?")
                }
                Section {
                    Toggle("Sista dag", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker("Datum", selection: $dueDate, displayedComponents: .date)
                    }
                }
                if hasDueDate {
                    Section {
                        Toggle("Kan göras från", isOn: $hasStartDate.animation())
                        if hasStartDate {
                            DatePicker("Datum", selection: $startDate, in: ...dueDate, displayedComponents: .date)
                        }
                    } footer: {
                        Text("För uppgifter som kan göras när som helst under en period, till exempel en helg.")
                    }
                }
                if let todo {
                    Section {
                        Button("Ta bort uppgiften", role: .destructive) {
                            todos.remove([todo])
                            dismiss()
                        }
                        .foregroundStyle(Color.danger)
                    }
                }
            }
            .navigationTitle(todo == nil ? "Ny uppgift" : "Ändra uppgift")
            .paperBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara", action: save)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func load() {
        guard let todo else {
            titleIsFocused = true
            return
        }
        title = todo.title
        notes = todo.notes ?? ""
        assignee = todo.assignee
        if let due = todo.dueDate.flatMap(LocalDay.date(from:)) {
            hasDueDate = true
            dueDate = due
        }
        if let start = todo.startDate.flatMap(LocalDay.date(from:)) {
            hasStartDate = true
            startDate = start
        }
    }

    private func save() {
        let due = hasDueDate ? LocalDay.string(from: dueDate) : nil
        let start = hasDueDate && hasStartDate ? LocalDay.string(from: min(startDate, dueDate)) : nil
        if let todo {
            todos.update(todo, title: trimmedTitle, notes: notes, assignee: assignee, startDate: start, dueDate: due)
        } else {
            todos.add(title: trimmedTitle, notes: notes, assignee: assignee, startDate: start, dueDate: due)
        }
        dismiss()
    }
}

// MARK: Städ

private struct ChoreSections: View {
    @Environment(AppSession.self) private var session
    let chores: ChoreList
    let filter: AssigneeFilter
    let edit: (Chore) -> Void

    var body: some View {
        let sorted = chores.sorted.filter { filter.includes($0.assignee) }
        if chores.records.isEmpty {
            EmptyCard(emoji: "🧽", text: "Inga städsysslor än. Lägg till det ni brukar göra med plusset, till exempel dammsuga varje vecka.")
        } else if sorted.isEmpty {
            EmptyCard(emoji: "🧽", text: "Inga städsysslor här.")
        }
        ForEach(sorted) { chore in
            ChoreRow(chore: chore, markDone: { chores.markDone(chore, by: session.me?.id) }, edit: { edit(chore) })
                .cardRow(stripe: session.color(for: chore.assignee))
        }
        .onDelete { offsets in offsets.forEach { chores.remove(sorted[$0]) } }
        if !sorted.isEmpty {
            Text("Tryck på bocken när sysslan är gjord. Tryck på namnet för att ändra den.")
                .font(.footnote)
                .foregroundStyle(Color.inkMuted)
                .plainRow(top: 8)
        }
    }
}

struct ChoreRow: View {
    @Environment(AppSession.self) private var session
    let chore: Chore
    let markDone: () -> Void
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            CheckButton(isOn: isDoneToday, accessibilityLabel: Text("Markera \(chore.title) som gjord"), action: markDone)
                .disabled(isDoneToday)

            VStack(alignment: .leading, spacing: 2) {
                Text(chore.title)
                    .foregroundStyle(Color.ink)
                Text(details)
                    .font(.footnote)
                    .foregroundStyle(Color.inkMuted)
            }
            .tapToEdit(edit)

            if let due = ChoreSchedule.dueLabel(chore), let daysLeft = ChoreSchedule.daysLeft(chore) {
                DueBadge(text: due, kind: DueBadge.Kind(daysLeft: daysLeft))
            }
        }
    }

    private var isDoneToday: Bool { ChoreSchedule.daysSinceDone(chore) == 0 }

    /// "↻ varje vecka · Gjord igår av Anna", med personen sysslan är för.
    private var details: String {
        let lastDone = ChoreSchedule.lastDoneLabel(chore, by: session.person(chore.lastDoneBy)?.name)
        let interval = chore.intervalDays.map { "↻ \(ChoreSchedule.intervalLabel(days: $0))" }
        return [session.name(for: chore.assignee), interval, lastDone].compactMap { $0 }.joined(separator: " · ")
    }
}

struct ChoreEditor: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let chores: ChoreList
    let chore: Chore?

    @State private var title = ""
    @State private var assignee: UUID?
    @State private var repeats = false
    @State private var count = 1
    @State private var unit = IntervalUnit.weeks
    @State private var hasBeenDone = false
    @State private var lastDone = Date.now
    @FocusState private var titleIsFocused: Bool

    enum IntervalUnit: CaseIterable {
        case weeks, days

        var title: LocalizedStringKey {
            switch self {
            case .weeks: "veckor"
            case .days: "dagar"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("T.ex. byta sängkläder", text: $title)
                        .focused($titleIsFocused)
                }
                Section {
                    AssigneePicker(assignee: $assignee)
                } header: {
                    FieldLabel("Vem gör det?")
                }
                Section {
                    Toggle("Återkommer", isOn: $repeats.animation())
                    if repeats {
                        Stepper(intervalText, value: $count, in: 1...52)
                        Picker("Enhet", selection: $unit) {
                            ForEach(IntervalUnit.allCases, id: \.self) { Text($0.title) }
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    FieldLabel("Hur ofta?")
                } footer: {
                    Text(repeats
                        ? "Nästa gång räknas från när sysslan senast gjordes."
                        : "Utan intervall visar listan bara när det gjordes senast och av vem.")
                }
                if chore != nil {
                    Section {
                        Toggle("Har gjorts", isOn: $hasBeenDone.animation())
                        if hasBeenDone {
                            DatePicker("Datum", selection: $lastDone, in: ...Date.now, displayedComponents: .date)
                        }
                    } header: {
                        FieldLabel("Senast gjord")
                    } footer: {
                        Text("Ändra här om sysslan bockades av av misstag.")
                    }
                    Section {
                        Button("Ta bort städsysslan", role: .destructive, action: remove)
                            .foregroundStyle(Color.danger)
                    }
                }
            }
            .navigationTitle(chore == nil ? "Ny städsyssla" : "Ändra städsyssla")
            .paperBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara", action: save)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var intervalDays: Int? {
        guard repeats else { return nil }
        return unit == .weeks ? count * 7 : count
    }

    /// "Varje vecka", "Varannan dag", "Var 3:e vecka"
    private var intervalText: String {
        let label = ChoreSchedule.intervalLabel(days: intervalDays ?? 7)
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    private func load() {
        guard let chore else {
            titleIsFocused = true
            return
        }
        title = chore.title
        assignee = chore.assignee
        if let days = chore.intervalDays {
            repeats = true
            (count, unit) = days % 7 == 0 ? (days / 7, .weeks) : (days, .days)
        }
        if let lastDoneAt = chore.lastDoneAt {
            hasBeenDone = true
            lastDone = lastDoneAt
        }
    }

    private func save() {
        guard let chore else {
            chores.add(title: trimmedTitle, assignee: assignee, intervalDays: intervalDays)
            dismiss()
            return
        }
        chores.update(chore, title: trimmedTitle, assignee: assignee, intervalDays: intervalDays)
        let doneOnBefore = chore.lastDoneAt.map(LocalDay.string(from:))
        let doneOnNow = hasBeenDone ? LocalDay.string(from: lastDone) : nil
        if doneOnNow != doneOnBefore {
            chores.setLastDone(chore, at: hasBeenDone ? lastDone : nil, by: chore.lastDoneBy ?? session.me?.id)
        }
        dismiss()
    }

    private func remove() {
        if let chore { chores.remove(chore) }
        dismiss()
    }
}
