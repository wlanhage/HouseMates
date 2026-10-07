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
    @State private var calendar = SharedCalendar()
    @State private var tab: AppTab = .shopping
    private let push = Push.shared

    var body: some View {
        TabView(selection: $tab) {
            ShoppingView(list: shopping)
                .tabItem { Label("Inköp", systemImage: "cart") }
                .tag(AppTab.shopping)
            CalendarView(calendar: calendar)
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
            await shopping.start(householdID: householdID)
        }
        .onChange(of: session.household, initial: true) { _, household in
            calendar.update(household: household)
        }
        .onChange(of: scenePhase) { _, phase in
            // Realtidsanslutningen kan ha brutits medan appen låg i bakgrunden.
            guard phase == .active else { return }
            Task { await shopping.sync() }
            calendar.refresh()
        }
        .onChange(of: push.openedTab) { _, opened in
            guard let opened else { return }
            tab = opened
            push.openedTab = nil
        }
        .onDisappear { Task { await shopping.stop() } }
    }
}
