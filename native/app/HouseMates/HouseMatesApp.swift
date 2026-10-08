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
    private let push = Push.shared

    var body: some View {
        TabView(selection: $tab) {
            HomeView(todos: todos, chores: chores, shopping: shopping, calendar: calendar, assignees: assignees)
                .tabItem { Label("Hem", systemImage: "house") }
                .tag(AppTab.home)
            ShoppingView(list: shopping, favorites: favorites)
                .tabItem { Label("Inköp", systemImage: "cart") }
                .tag(AppTab.shopping)
            HouseworkView(todos: todos, chores: chores)
                .tabItem { Label("Att göra", systemImage: "checklist") }
                .tag(AppTab.todos)
            CalendarView(calendar: calendar, assignees: assignees)
                .tabItem { Label("Kalender", systemImage: "calendar") }
                .tag(AppTab.calendar)
            SettingsView(calendar: calendar)
                .tabItem { Label("Inställningar", systemImage: "gearshape") }
                .tag(AppTab.settings)
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
