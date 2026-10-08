import EventKit
import SwiftUI

/// Hem: det som gäller idag, och vad som hänt på inköpslistan.
struct HomeView: View {
    @Environment(AppSession.self) private var session
    let todos: TodoList
    let chores: ChoreList
    let shopping: ShoppingList
    let calendar: SharedCalendar
    let assignees: EventAssigneeList
    @State private var feed: [ActivityGroup] = []
    @State private var editing: HouseworkView.Editing?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if todayEvents.isEmpty && todayTodos.isEmpty && todayChores.isEmpty {
                        Text("Inget planerat idag.").foregroundStyle(.secondary)
                    }
                    ForEach(todayEvents, id: \.self) { event in
                        TodayEventRow(event: event, assignee: assignees.assignee(for: event.calendarItemExternalIdentifier))
                    }
                    ForEach(todayTodos) { todo in
                        TodoRow(todo: todo, toggle: { todos.toggle(todo, by: session.me?.id) }, edit: { editing = .todo(todo) })
                    }
                    ForEach(todayChores) { chore in
                        ChoreRow(chore: chore, markDone: { chores.markDone(chore, by: session.me?.id) }, edit: { editing = .chore(chore) })
                    }
                } header: {
                    Text(todayTitle)
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

    /// "Onsdag 7 oktober"
    private var todayTitle: String {
        let date = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "sv_SE")))
        return date.prefix(1).uppercased() + date.dropFirst()
    }

    /// Händelser som pågår idag, också sådana som började tidigare.
    private var todayEvents: [EKEvent] {
        calendar.upcoming.first { Calendar.current.isDateInToday($0.day) }?.events ?? []
    }

    /// Uppgifter med sista dag idag, och försenade.
    private var todayTodos: [Todo] {
        let today = LocalDay.string(from: .now)
        return todos.open.filter { $0.dueDate.map { $0 <= today } ?? false }
    }

    private var todayChores: [Chore] {
        chores.sorted.filter { (ChoreSchedule.daysLeft($0) ?? 1) <= 0 }
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
