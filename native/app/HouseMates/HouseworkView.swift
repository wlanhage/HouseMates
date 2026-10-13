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
                Picker("Visa", selection: $part) {
                    Text("Uppgifter").tag(Part.todos)
                    Text("Städ").tag(Part.chores)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)

                FilterPills(filter: $filter)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                if todos.isOffline || chores.isOffline {
                    Section {
                        OfflineNotice(hasPending: !todos.pending.isEmpty || !chores.pending.isEmpty)
                    }
                }

                switch part {
                case .todos: TodoSections(todos: todos, filter: filter) { editing = .todo($0) }
                case .chores: ChoreSections(chores: chores, filter: filter) { editing = .chore($0) }
                }
            }
            .navigationTitle("Att göra")
            .onChange(of: session.partner?.id) { filter = .everyone }
            .toolbar {
                Button {
                    editing = part == .todos ? .todo(nil) : .chore(nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(part == .todos ? "Ny uppgift" : "Ny städsyssla")
            }
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

    /// Det som redigeras i arket; nil betyder en ny uppgift eller syssla.
    enum Editing: Identifiable {
        case todo(Todo?)
        case chore(Chore?)

        var id: String {
            switch self {
            case let .todo(todo): "uppgift-\(todo?.id.uuidString ?? "ny")"
            case let .chore(chore): "syssla-\(chore?.id.uuidString ?? "ny")"
            }
        }
    }
}

/// Alla, Du, partnern eller Gemensamt, som i webbappen. Gäller öppna uppgifter och städsysslor.
private struct FilterPills: View {
    @Environment(AppSession.self) private var session
    @Binding var filter: AssigneeFilter

    var body: some View {
        HStack(spacing: 8) {
            ForEach(filters, id: \.self) { option in
                Button {
                    filter = option
                } label: {
                    Text(name(for: option))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .foregroundStyle(option == filter ? Color.white : Color.primary)
                        .background(option == filter ? color(for: option) : Color(.tertiarySystemFill), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option == filter ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }

    private var filters: [AssigneeFilter] {
        [.everyone] + [session.me, session.partner].compactMap { $0 }.map { .person($0.id) } + [.shared]
    }

    private func name(for filter: AssigneeFilter) -> String {
        switch filter {
        case .everyone: "Alla"
        case let .person(id): id == session.me?.id ? "Du" : session.name(for: id)
        case .shared: "Gemensamt"
        }
    }

    private func color(for filter: AssigneeFilter) -> Color {
        switch filter {
        case .everyone: .accentColor
        case let .person(id): session.color(for: id)
        case .shared: .shared
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

    var body: some View {
        let open = todos.open.filter { filter.includes(session.person($0.assignee)?.id) }
        let finished = todos.finished
        Section {
            if open.isEmpty {
                Text(filter == .everyone ? "Inga öppna uppgifter." : "Inga öppna uppgifter här.")
                    .foregroundStyle(.secondary)
            }
            ForEach(open) { todo in
                TodoRow(todo: todo, toggle: { todos.toggle(todo, by: session.me?.id) }, edit: { edit(todo) })
            }
            .onDelete { offsets in todos.remove(offsets.map { open[$0] }) }
        }
        if !finished.isEmpty {
            Section {
                ForEach(finished) { todo in
                    TodoRow(todo: todo, toggle: { todos.toggle(todo, by: session.me?.id) }, edit: { edit(todo) })
                }
                .onDelete { offsets in todos.remove(offsets.map { finished[$0] }) }
            } header: {
                HStack {
                    Text("Klart")
                    Spacer()
                    Button("Rensa") { todos.clearFinished() }
                        .font(.subheadline)
                }
            }
        }
    }
}

struct TodoRow: View {
    let todo: Todo
    let toggle: () -> Void
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: toggle) {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.done ? Color.green : Color.secondary)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(todo.done ? "Markera \(todo.title) som inte klar" : "Markera \(todo.title) som klar")

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .strikethrough(todo.done)
                    .foregroundStyle(todo.done ? .secondary : .primary)
                if let notes = todo.notes {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    PersonLabel(assignee: todo.assignee)
                    if let when {
                        Text("·")
                        Text(isOverdue ? "\(when) · försenad" : when)
                            .foregroundStyle(isOverdue ? Color.red : Color.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .tapToEdit(edit)
        }
    }

    private var isOverdue: Bool {
        guard !todo.done, let due = todo.dueDate else { return false }
        return (LocalDay.days(until: due) ?? 0) < 0
    }

    /// "Imorgon", eller "fre 10 okt–sön 12 okt" för en period.
    private var when: String? {
        guard let due = todo.dueDate else { return nil }
        guard let start = todo.startDate else { return LocalDay.label(due) }
        return "\(LocalDay.label(start))–\(LocalDay.label(due).lowercased())"
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
                Section("Vem gör det?") {
                    AssigneePicker(assignee: $assignee)
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
                    }
                }
            }
            .navigationTitle(todo == nil ? "Ny uppgift" : "Ändra uppgift")
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
        let sorted = chores.sorted.filter { filter.includes(session.person($0.assignee)?.id) }
        Section {
            if chores.records.isEmpty {
                Text("Inga städsysslor än. Lägg till det ni brukar göra, till exempel dammsuga varje vecka.")
                    .foregroundStyle(.secondary)
            } else if sorted.isEmpty {
                Text("Inga städsysslor här.").foregroundStyle(.secondary)
            }
            ForEach(sorted) { chore in
                ChoreRow(chore: chore, markDone: { chores.markDone(chore, by: session.me?.id) }, edit: { edit(chore) })
            }
            .onDelete { offsets in offsets.forEach { chores.remove(sorted[$0]) } }
        } footer: {
            if !sorted.isEmpty {
                Text("Tryck på Klar när sysslan är gjord. Tryck på namnet för att ändra den.")
            }
        }
    }
}

struct ChoreRow: View {
    @Environment(AppSession.self) private var session
    let chore: Chore
    let markDone: () -> Void
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(chore.title)
                HStack(spacing: 6) {
                    PersonLabel(assignee: chore.assignee)
                    if let interval = chore.intervalDays {
                        Text("·")
                        Text(ChoreSchedule.intervalLabel(days: interval))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(isOverdue ? Color.red : Color.secondary)
            }
            .tapToEdit(edit)

            Button("Klar", action: markDone)
                .buttonStyle(.bordered)
                .disabled(isDoneToday)
                .accessibilityLabel("Markera \(chore.title) som gjord")
        }
    }

    private var isDoneToday: Bool { ChoreSchedule.daysSinceDone(chore) == 0 }

    private var isOverdue: Bool { (ChoreSchedule.daysLeft(chore) ?? 0) < 0 }

    /// "Gjord igår av Anna · Om 6 dagar"
    private var status: String {
        var lastDone = ChoreSchedule.lastDoneLabel(chore)
        if chore.lastDoneAt != nil, let by = session.person(chore.lastDoneBy) {
            lastDone += " av \(by.name)"
        }
        return [lastDone, ChoreSchedule.dueLabel(chore)].compactMap { $0 }.joined(separator: " · ")
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

    enum IntervalUnit: String, CaseIterable {
        case weeks = "veckor"
        case days = "dagar"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("T.ex. byta sängkläder", text: $title)
                        .focused($titleIsFocused)
                }
                Section("Vem gör det?") {
                    AssigneePicker(assignee: $assignee)
                }
                Section {
                    Toggle("Återkommer", isOn: $repeats.animation())
                    if repeats {
                        Stepper(intervalText, value: $count, in: 1...52)
                        Picker("Enhet", selection: $unit) {
                            ForEach(IntervalUnit.allCases, id: \.self) { Text($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Text("Hur ofta?")
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
                        Text("Senast gjord")
                    } footer: {
                        Text("Ändra här om sysslan bockades av av misstag.")
                    }
                    Section {
                        Button("Ta bort städsysslan", role: .destructive, action: remove)
                    }
                }
            }
            .navigationTitle(chore == nil ? "Ny städsyssla" : "Ändra städsyssla")
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
