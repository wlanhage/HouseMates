import EventKit
import SwiftUI

/// Hem: en dag i taget (idag först), och vad som hänt på inköpslistan.
struct HomeView: View {
    @Environment(AppSession.self) private var session
    let todos: TodoList
    let chores: ChoreList
    let shopping: ShoppingList
    let calendar: SharedCalendar
    let assignees: EventAssigneeList
    @State private var feed: [ActivityGroup] = []
    @State private var editing: HouseworkView.Editing?
    /// Dagar från idag, inom `HomeDay.offsets`.
    @State private var dayOffset = 0

    var body: some View {
        let today = LocalDay.string(from: .now)
        let day = LocalDay.adding(dayOffset, to: today) ?? today
        let dayEvents = calendar.eventsByDay(from: day, through: day)[day] ?? []
        let dayTodos = HomeDay.todos(todos.open, on: day, today: today)
        let dayChores = ChoreSchedule.byDueDay(chores.sorted, overdueOn: today)[day] ?? []
        NavigationStack {
            List {
                Section {
                    Group {
                        if dayEvents.isEmpty && dayTodos.isEmpty && dayChores.isEmpty {
                            Text("Inget planerat \(LocalDay.label(day).lowercased()).").foregroundStyle(.secondary)
                        }
                        ForEach(dayEvents, id: \.self) { event in
                            TodayEventRow(event: event, assignee: assignees.assignee(for: event.calendarItemExternalIdentifier))
                        }
                        ForEach(dayTodos) { todo in
                            TodoRow(todo: todo, toggle: { todos.toggle(todo, by: session.me?.id) }, edit: { editing = .todo(todo) })
                        }
                        ForEach(dayChores) { chore in
                            ChoreRow(chore: chore, markDone: { chores.markDone(chore, by: session.me?.id) }, edit: { editing = .chore(chore) })
                        }
                    }
                    .simultaneousGesture(daySwipe)
                } header: {
                    DayHeader(day: day, offset: $dayOffset)
                }
                Section("Nyligen i inköp") {
                    if feed.isEmpty {
                        Text("Inget har hänt på listan än.").foregroundStyle(.secondary)
                    }
                    ForEach(feed) { group in
                        FeedRow(group: group)
                    }
                }
            }
            .navigationTitle(greeting)
            .refreshable {
                await todos.sync()
                await chores.sync()
                calendar.refresh()
                await loadFeed()
            }
            .undoBanner(for: todos)
            .undoBanner(for: chores)
            // Hämtar om flödet när listan ändras, också när partnern ändrar den.
            .task(id: shopping.records) { await loadFeed() }
            .sheet(item: $editing) { editing in
                switch editing {
                case let .todo(todo): TodoEditor(todos: todos, todo: todo)
                case let .chore(chore): ChoreEditor(chores: chores, chore: chore)
                }
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let hello = switch hour {
        case ..<5: "God natt"
        case ..<10: "God morgon"
        case ..<18: "Hej"
        default: "God kväll"
        }
        return session.me.map { "\(hello), \($0.name)" } ?? hello
    }

    /// Ett svep åt vänster visar nästa dag, åt höger dagen före, som i webbappen.
    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { drag in
            let width = drag.translation.width
            guard abs(width) > 55, abs(width) > abs(drag.translation.height) else { return }
            let next = dayOffset + (width < 0 ? 1 : -1)
            if HomeDay.offsets.contains(next) {
                withAnimation { dayOffset = next }
            }
        }
    }

    private func loadFeed() async {
        do {
            let activities: [Activity] = try await Backend.client.from("activity_log")
                .select("id, actor, type, payload, created_at")
                .in("type", values: ShoppingFeed.types)
                .order("id", ascending: false)
                .limit(60)
                .execute()
                .value
            feed = ShoppingFeed.groups(activities)
        } catch {
            // Utan nät visas det som redan hämtats.
        }
    }
}

/// Det som hör till en dag på Hem, med samma regler som webbappen.
enum HomeDay {
    /// En vecka bakåt och sex framåt, som webbappens dagsbläddring.
    static let offsets = -7...42

    /// Uppgifter med sista dag den dagen, och idag också försenade. En period syns på sin sista dag.
    static func todos(_ open: [Todo], on day: String, today: String) -> [Todo] {
        open.filter { todo in
            guard let due = todo.dueDate else { return false }
            return due == day || (day == today && due < today)
        }
    }
}

/// Pilar, dagens rubrik ("Idag", "Imorgon", "mån 15 jul") och "Till idag" när man bläddrat bort.
private struct DayHeader: View {
    let day: String
    @Binding var offset: Int

    var body: some View {
        HStack {
            arrow("chevron.left", label: "Föregående dag", step: -1)
            Spacer()
            VStack(spacing: 2) {
                Text(LocalDay.label(day))
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                if offset != 0 {
                    Button("Till idag") { withAnimation { offset = 0 } }
                        .font(.caption)
                }
            }
            Spacer()
            arrow("chevron.right", label: "Nästa dag", step: 1)
        }
        .textCase(nil)
        .buttonStyle(.borderless)
    }

    private func arrow(_ systemName: String, label: String, step: Int) -> some View {
        Button {
            withAnimation { offset += step }
        } label: {
            Image(systemName: systemName)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .disabled(!HomeDay.offsets.contains(offset + step))
        .accessibilityLabel(label)
    }
}

private struct TodayEventRow: View {
    let event: EKEvent
    let assignee: UUID?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? "")
                PersonLabel(assignee: assignee)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(event.isAllDay ? "Heldag" : event.startDate.formatted(date: .omitted, time: .shortened))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// "Anna la till 3 varor", med varorna under ett tryck.
private struct FeedRow: View {
    @Environment(AppSession.self) private var session
    let group: ActivityGroup

    var body: some View {
        if group.entries.count > 1 {
            DisclosureGroup {
                ForEach(group.entries) { entry in
                    Text(entry.payload?.name ?? "")
                        .foregroundStyle(.secondary)
                }
            } label: {
                summary
            }
        } else {
            summary
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(session.color(for: group.actor))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.person(group.actor)?.name ?? "Någon") \(ShoppingFeed.describe(group))")
                Text(Self.relative.localizedString(for: group.newest, relativeTo: .now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateTimeStyle = .named
        return formatter
    }()
}
