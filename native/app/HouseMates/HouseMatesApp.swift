import SwiftUI

@main
struct HouseMatesApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .task { await session.start() }
        }
    }
}

struct RootView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var session = session
        Group {
            switch session.phase {
            case .loading: LoadingView()
            case .signedOut: AuthView()
            case .needsHousehold: HouseholdSetupView()
            case .ready: MainTabs()
            }
        }
        .onOpenURL { url in Task { await session.handle(url) } }
        .sheet(isPresented: $session.needsNewPassword) { NewPasswordView() }
        .alert("Länken fungerade inte", isPresented: linkErrorIsShown) {
            Button("OK") {}
        } message: {
            Text(session.linkError ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await session.reload() } }
        }
    }

    private var linkErrorIsShown: Binding<Bool> {
        Binding(get: { session.linkError != nil }, set: { if !$0 { session.linkError = nil } })
    }
}

private struct LoadingView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        VStack(spacing: 16) {
            if let error = session.loadError {
                Text(error).multilineTextAlignment(.center)
                Button("Försök igen") { Task { await session.reload() } }
            } else {
                ProgressView()
            }
        }
        .padding()
    }
}

struct MainTabs: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var shopping = ShoppingList()
    @State private var todos = TodoList()
    @State private var chores = ChoreList()
    @State private var favorites = FavoriteList()
    @State private var assignees = EventAssigneeList()
    @State private var calendar = SharedCalendar()
    @State private var tab: AppTab = .home
    @State private var choosesNew = false
    @State private var creating: NewThing?
    @State private var createsEvent = false
    @State private var isKeyboardVisible = false
    private let push = Push.shared

    /// Det plusset kan lägga till, utom händelser som skapas i Kalender-fliken.
    enum NewThing: Identifiable {
        case item, todo, chore
        var id: Self { self }
    }

    var body: some View {
        @Bindable var session = session
        // Flikarna i webbappens ordning, med en egen flikrad (TabBar) i stället för iOS egen.
        TabView(selection: $tab) {
            HomeView(todos: todos, chores: chores, shopping: shopping, calendar: calendar, assignees: assignees)
                .tag(AppTab.home)
                .toolbar(.hidden, for: .tabBar)
            CalendarView(calendar: calendar, assignees: assignees, chores: chores, createsEvent: $createsEvent)
                .tag(AppTab.calendar)
                .toolbar(.hidden, for: .tabBar)
            ShoppingView(list: shopping, favorites: favorites)
                .tag(AppTab.shopping)
                .toolbar(.hidden, for: .tabBar)
            HouseworkView(todos: todos, chores: chores)
                .tag(AppTab.todos)
                .toolbar(.hidden, for: .tabBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Göms medan tangentbordet är uppe, som iOS egen flikrad.
            if !isKeyboardVisible {
                TabBar(selection: $tab) { choosesNew = true }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .confirmationDialog("Lägg till", isPresented: $choosesNew) {
            Button("Ny händelse") {
                tab = .calendar
                createsEvent = true
            }
            Button("Ny vara") { creating = .item }
            Button("Ny uppgift") { creating = .todo }
            Button("Ny städsyssla") { creating = .chore }
        }
        .sheet(item: $creating) { thing in
            switch thing {
            case .item: NewItemSheet(list: shopping)
            case .todo: TodoEditor(todos: todos, todo: nil)
            case .chore: ChoreEditor(chores: chores, chore: nil)
            }
        }
        .sheet(isPresented: $session.showsSettings) {
            SettingsView(calendar: calendar)
        }
        .task(id: session.household?.id) {
            guard let householdID = session.household?.id else { return }
            // Notisbehörigheten läses först, så att notiskortet inte blinkar fram medan listan synkar.
            await push.registerIfAllowed()
            shopping.start(householdID: householdID)
            todos.start(householdID: householdID)
            chores.start(householdID: householdID)
            favorites.start(householdID: householdID)
            assignees.start(householdID: householdID)
            await NotificationPrefs.syncTimeZone()
            await favorites.importSharedLinks()
        }
        .onChange(of: session.household, initial: true) { _, household in
            calendar.update(household: household)
        }
        .onChange(of: scenePhase) { _, phase in
            // Realtidsanslutningen kan ha brutits medan appen låg i bakgrunden.
            guard phase == .active else { return }
            // Notiser kan ha slagits på i Inställningar, och telefonen kan ha bytt tidszon.
            Task {
                await push.registerIfAllowed()
                await NotificationPrefs.syncTimeZone()
            }
            Task { await shopping.sync() }
            Task { await todos.sync() }
            Task { await chores.sync() }
            Task { await assignees.sync() }
            Task {
                await favorites.sync()
                await favorites.importSharedLinks()
            }
            calendar.refresh()
        }
        .onChange(of: calendar.uidsToSave) { _, uids in
            guard let uids, let title = calendar.linkedCalendar?.title else { return }
            Task { try? await session.saveCalendarLink(title: title, eventUIDs: uids) }
        }
        // initial: ett tryck på en notis kan komma innan flikarna finns (när appen startas av trycket).
        .onChange(of: push.openedTab, initial: true) { _, opened in
            guard let opened else { return }
            tab = opened
            push.openedTab = nil
        }
        .onDisappear {
            session.showsSettings = false
            Task {
                await shopping.stop()
                await todos.stop()
                await chores.stop()
                await favorites.stop()
                await assignees.stop()
            }
        }
    }
}
