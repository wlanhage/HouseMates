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
                PageTitle("Inköp") {
                    Button { showsFavorites = true } label: {
                        Label("Middagar", systemImage: "fork.knife")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.accent.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Våra middagar")
                }
                if list.isOffline {
                    OfflineNotice(hasPending: !list.pending.isEmpty)
                }
                if push.authorization == .notDetermined && !hidesNotificationCard {
                    NotificationCard(partnerName: session.partner?.name) { hidesNotificationCard = true }
                }
                HStack(spacing: 8) {
                    TextField("Lägg till vara", text: $newItem)
                        .focused($focus, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { add() }
                        .paperField(isFocused: focus == .name)
                    if !newItem.isEmpty {
                        TextField("Antal", text: $qty)
                            .focused($focus, equals: .qty)
                            .submitLabel(.next)
                            .onSubmit { add() }
                            .frame(width: 56)
                            .paperField(isFocused: focus == .qty)
                            .accessibilityLabel("Antal (valfritt)")
                    }
                    Button { add() } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.bold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Lägg till")
                }
                .plainRow(top: 8)
                if focus != nil && !shownSuggestions.isEmpty {
                    SuggestionChips(names: shownSuggestions) { add($0) }
                        .plainRow(top: 2)
                }
                if let alreadyOnList {
                    Text("Står redan på listan: \(alreadyOnList)")
                        .font(.footnote)
                        .foregroundStyle(Color.inkMuted)
                        .plainRow(top: 0)
                }
                if list.open.isEmpty && list.bought.isEmpty {
                    EmptyCard(emoji: "🛒", text: "Listan är tom. Lägg till något ovan.")
                }
                ForEach(list.open) { item in
                    ItemRow(item: item) { list.toggle(item, by: session.me?.id) }
                        .cardRow()
                }
                .onDelete { remove(at: $0, in: list.open) }
                if !list.bought.isEmpty {
                    SectionTitle("Handlat · \(list.bought.count)") {
                        Button("Rensa") { list.clearBought() }
                            .buttonStyle(SmallButtonStyle())
                    }
                    .plainRow(top: 16, bottom: 4)
                    ForEach(list.bought) { item in
                        ItemRow(item: item) { list.toggle(item, by: session.me?.id) }
                            .cardRow()
                    }
                    .onDelete { remove(at: $0, in: list.bought) }
                }
            }
            .listStyle(.plain)
            .paperBackground()
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { AppTopBar() }
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

/// "Ny vara" från plusset i flikraden: vara och antal, som i webbappen.
struct NewItemSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let list: ShoppingList
    @State private var name = ""
    @State private var qty = ""
    @State private var isAlreadyOnList = false
    @FocusState private var nameIsFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Vara", text: $name)
                        .focused($nameIsFocused)
                        .onSubmit(add)
                    TextField("Antal (valfritt)", text: $qty)
                        .onSubmit(add)
                } footer: {
                    if isAlreadyOnList {
                        Text("Står redan på listan.")
                    }
                }
            }
            .navigationTitle("Ny vara")
            .paperBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lägg till", action: add)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { nameIsFocused = true }
            .onChange(of: name) { isAlreadyOnList = false }
        }
        .presentationDetents([.medium])
    }

    private func add() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if list.add(name, qty: qty, by: session.me?.id) {
            dismiss()
        } else {
            isAlreadyOnList = true
        }
    }
}

/// Tidigare varor att lägga till med ett tryck, som i webbappen.
private struct SuggestionChips: View {
    let names: [String]
    let add: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(names, id: \.self) { name in
                    Button(name) { add(name) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.surfaceSecondary, in: Capsule())
                        .overlay { Capsule().strokeBorder(Color.hairline) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Lägger till på listan")
                }
            }
            .padding(8)
        }
        .scrollIndicators(.hidden)
        .card()
    }
}

/// En prick i färgen hos den som lade till varan; på en handlad vara står vem som handlade den.
private struct ItemRow: View {
    @Environment(AppSession.self) private var session
    let item: ShoppingItem
    let toggle: () -> Void

    var body: some View {
        CheckButton(isOn: item.checked, accessibilityLabel: item.qty.map { "\(item.name), \($0)" } ?? item.name, action: toggle) {
            HStack {
                Text(item.name)
                    .strikethrough(item.checked)
                    .foregroundStyle(item.checked ? Color.inkMuted : Color.ink)
                if let qty = item.qty {
                    Text("· \(qty)").foregroundStyle(Color.inkMuted)
                }
                Spacer()
                if item.checked, let buyer = session.person(item.checkedBy) {
                    PersonAvatar(assignee: buyer.id)
                } else if !item.checked, let adder = session.person(item.createdBy) {
                    Circle()
                        .fill(Color(hex: adder.color))
                        .frame(width: 9, height: 9)
                }
            }
        }
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Få en notis när \(partnerName ?? "din partner") ändrar listorna eller kalendern.")
                .foregroundStyle(Color.ink)
            HStack(spacing: 14) {
                Button("Slå på notiser") { Task { await Push.shared.requestPermission() } }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Inte nu", action: dismiss)
                    .buttonStyle(.borderless)
            }
        }
        .cardRow()
    }
}
