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
                if shopping.isOffline || todos.isOffline || chores.isOffline {
                    OfflineNotice(hasPending: !shopping.pending.isEmpty || !todos.pending.isEmpty || !chores.pending.isEmpty)
                }
                DayHeader(day: day, offset: $dayOffset)
                    .plainRow(top: 6, bottom: 6)
                Group {
                    if dayEvents.isEmpty && dayTodos.isEmpty && dayChores.isEmpty {
                        Text("Inget planerat \(LocalDay.label(day).lowercased()).")
                            .foregroundStyle(Color.inkMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .plainRow()
                    }
                    ForEach(dayEvents, id: \.self) { event in
                        TodayEventRow(event: event, assignee: assignees.assignee(for: event.calendarItemExternalIdentifier))
                            .cardRow()
                    }
                    ForEach(dayTodos) { todo in
                        TodoRow(todo: todo, toggle: { todos.toggle(todo, by: session.me?.id) }, edit: { editing = .todo(todo) })
                            .cardRow()
                    }
                    ForEach(dayChores) { chore in
                        ChoreRow(chore: chore, markDone: { chores.markDone(chore, by: session.me?.id) }, edit: { editing = .chore(chore) })
                            .cardRow(stripe: session.color(for: chore.assignee))
                    }
                }
                .simultaneousGesture(daySwipe)
                SectionTitle("Nyligen i inköp")
                    .plainRow(top: 20, bottom: 4)
                if feed.isEmpty {
                    Text("Inget har hänt på listan än.")
                        .foregroundStyle(Color.inkMuted)
                        .plainRow()
                }
                ForEach(feed) { group in
                    FeedRow(group: group)
                        .cardRow()
                }
            }
            .listStyle(.plain)
            .navigationTitle(greeting)
            .paperBackground()
            .toolbar { SettingsButton() }
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
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Color.ink)
                if offset != 0 {
                    Button("Till idag") { withAnimation { offset = 0 } }
                        .font(.caption.weight(.bold))
                }
            }
            Spacer()
            arrow("chevron.right", label: "Nästa dag", step: 1)
        }
        .buttonStyle(.borderless)
    }

    /// En rund pil med tunn kant, som i webbappen, men med en träffyta stor nog för ett finger.
    private func arrow(_ systemName: String, label: String, step: Int) -> some View {
        let isPossible = HomeDay.offsets.contains(offset + step)
        return Button {
            withAnimation { offset += step }
        } label: {
            Image(systemName: systemName)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color.inkMuted)
                .frame(width: 34, height: 34)
                .background(Color.surface, in: Circle())
                .overlay { Circle().strokeBorder(Color.hairline) }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .opacity(isPossible ? 1 : 0.35)
        }
        .disabled(!isPossible)
        .accessibilityLabel(label)
    }
}

/// En prick i färgen hos den händelsen är för, titeln och tiden, som i webbappen.
private struct TodayEventRow: View {
    @Environment(AppSession.self) private var session
    let event: EKEvent
    let assignee: UUID?

    var body: some View {
        HStack(spacing: 11) {
            Circle()
                .fill(session.color(for: assignee))
                .frame(width: 9, height: 9)
            Text(event.title ?? "")
                .foregroundStyle(Color.ink)
            Spacer()
            Text(event.isAllDay ? "Heldag" : event.startDate.formatted(date: .omitted, time: .shortened))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Color.inkMuted)
        }
        .frame(minHeight: 28)
        .accessibilityElement(children: .combine)
        .accessibilityValue(session.name(for: assignee))
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
                        .foregroundStyle(Color.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 39)
                        .padding(.top, 6)
                }
            } label: {
                summary
            }
        } else {
            summary
        }
    }

    private var summary: some View {
        HStack(spacing: 11) {
            PersonAvatar(assignee: group.actor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(actorName) \(ShoppingFeed.describe(group))")
                    .foregroundStyle(Color.ink)
                Text(Self.relative.localizedString(for: group.newest, relativeTo: .now))
                    .font(.footnote)
                    .foregroundStyle(Color.inkMuted)
            }
        }
    }

    /// "Du" för det man gjort själv, som i webbappen.
    private var actorName: String {
        if group.actor == session.me?.id { return "Du" }
        return session.person(group.actor)?.name ?? "Någon"
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        formatter.dateTimeStyle = .named
        return formatter
    }()
}
