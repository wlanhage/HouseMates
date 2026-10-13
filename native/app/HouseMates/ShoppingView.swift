import SwiftUI

struct ShoppingView: View {
    @Environment(AppSession.self) private var session
    let list: ShoppingList
    let favorites: FavoriteList
    @State private var newItem = ""
    @State private var qty = ""
    @State private var suggestions: [String] = []
    @State private var alreadyOnList: String?
    @State private var showsFavorites = false
    @FocusState private var focus: Field?
    @AppStorage("notiskort-dolt") private var hidesNotificationCard = false
    private let push = Push.shared

    var body: some View {
        NavigationStack {
            List {
                if list.isOffline {
                    OfflineNotice(hasPending: !list.pending.isEmpty)
                }
                if push.authorization == .notDetermined && !hidesNotificationCard {
                    NotificationCard(partnerName: session.partner?.name) { hidesNotificationCard = true }
                }
                Section {
                    HStack {
                        TextField("Lägg till vara", text: $newItem)
                            .focused($focus, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { add() }
                        if !newItem.isEmpty {
                            TextField("Antal", text: $qty)
                                .focused($focus, equals: .qty)
                                .submitLabel(.next)
                                .onSubmit { add() }
                                .frame(width: 64)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                                .accessibilityLabel("Antal (valfritt)")
                            Button("Lägg till") { add() }
                        }
                    }
                    if focus != nil && !shownSuggestions.isEmpty {
                        SuggestionChips(names: shownSuggestions) { add($0) }
                    }
                } footer: {
                    if let alreadyOnList {
                        Text("Står redan på listan: \(alreadyOnList)")
                    }
                }
                Section {
                    if list.open.isEmpty {
                        Text("Inget att handla.").foregroundStyle(.secondary)
                    }
                    ForEach(list.open) { item in
                        ItemRow(item: item) { list.toggle(item, by: session.me?.id) }
                    }
                    .onDelete { remove(at: $0, in: list.open) }
                }
                if !list.bought.isEmpty {
                    Section {
                        ForEach(list.bought) { item in
                            ItemRow(item: item) { list.toggle(item, by: session.me?.id) }
                        }
                        .onDelete { remove(at: $0, in: list.bought) }
                    } header: {
                        HStack {
                            Text("Handlat")
                            Spacer()
                            Button("Rensa") { list.clearBought() }
                                .font(.subheadline)
                        }
                    }
                }
            }
            .navigationTitle("Inköp")
            .toolbar {
                Button("Middagar", systemImage: "fork.knife") { showsFavorites = true }
                    .labelStyle(.titleAndIcon)
            }
            .sheet(isPresented: $showsFavorites) {
                FavoritesView(favorites: favorites, shopping: list)
            }
            .refreshable { await list.sync() }
            .undoBanner(for: list)
            .onChange(of: newItem) { if !newItem.isEmpty { alreadyOnList = nil } }
            .task(id: focus == nil ? nil : newItem) { await loadSuggestions() }
            .alert("Något gick fel", isPresented: errorIsShown) {
                Button("OK") {}
            } message: {
                Text(list.errorMessage ?? "")
            }
        }
    }

    private var errorIsShown: Binding<Bool> {
        Binding(get: { list.errorMessage != nil }, set: { if !$0 { list.errorMessage = nil } })
    }

    private enum Field { case name, qty }

    /// Det som redan står på listan föreslås inte, också när det nyss lagts till utan nät.
    private var shownSuggestions: [String] {
        suggestions.filter { !list.isOnList($0) }
    }

    private func add(_ suggestion: String? = nil) {
        let name = (suggestion ?? newItem).trimmingCharacters(in: .whitespacesAndNewlines)
        let wasAdded = list.add(name, qty: qty, by: session.me?.id)
        newItem = ""
        qty = ""
        focus = .name
        alreadyOnList = wasAdded || name.isEmpty ? nil : name
    }

    /// Väntar en kort stund efter varje tangent, så att inte varje bokstav blir ett anrop.
    private func loadSuggestions() async {
        guard focus != nil else {
            suggestions = []
            return
        }
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        suggestions = await list.suggestions(startingWith: newItem.trimmingCharacters(in: .whitespaces))
    }

    private func remove(at offsets: IndexSet, in items: [ShoppingItem]) {
        list.remove(offsets.map { items[$0] })
    }
}

/// Tidigare varor att lägga till med ett tryck, som i webbappen.
private struct SuggestionChips: View {
    let names: [String]
    let add: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(names, id: \.self) { name in
                    Button(name) { add(name) }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .accessibilityHint("Lägger till på listan")
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

/// En prick i färgen hos den som lade till varan; på en handlad vara står vem som handlade den.
private struct ItemRow: View {
    @Environment(AppSession.self) private var session
    let item: ShoppingItem
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack {
                Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.checked ? Color.green : Color.secondary)
                    .accessibilityHidden(true)
                Text(item.name)
                    .strikethrough(item.checked)
                    .foregroundStyle(item.checked ? .secondary : .primary)
                if let qty = item.qty {
                    Text(qty).foregroundStyle(.secondary)
                }
                Spacer()
                if item.checked, let buyer = session.person(item.checkedBy) {
                    PersonLabel(assignee: buyer.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !item.checked, let adder = session.person(item.createdBy) {
                    Circle()
                        .fill(Color(hex: adder.color))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .foregroundStyle(.primary)
        .accessibilityValue(accessibilityValue)
    }

    /// "Handlad av Anna", "Tillagd av William"
    private var accessibilityValue: String {
        if item.checked {
            return session.person(item.checkedBy).map { "Handlad av \($0.name)" } ?? "Handlad"
        }
        return session.person(item.createdBy).map { "Tillagd av \($0.name)" } ?? ""
    }
}

private struct NotificationCard: View {
    let partnerName: String?
    let dismiss: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Få en notis när \(partnerName ?? "din partner") ändrar listorna eller kalendern.")
                HStack {
                    Button("Slå på notiser") { Task { await Push.shared.requestPermission() } }
                        .buttonStyle(.borderedProminent)
                    Button("Inte nu", action: dismiss)
                        .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
