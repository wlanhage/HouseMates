import SwiftUI

struct ShoppingView: View {
    @Environment(AppSession.self) private var session
    let list: ShoppingList
    let favorites: FavoriteList
    @State private var newItem = ""
    @State private var alreadyOnList: String?
    @State private var showsFavorites = false
    @FocusState private var isAdding: Bool
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
                            .focused($isAdding)
                            .submitLabel(.next)
                            .onSubmit(add)
                        if !newItem.isEmpty {
                            Button("Lägg till", action: add)
                        }
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
                        ItemRow(item: item) { list.toggle(item) }
                    }
                    .onDelete { remove(at: $0, in: list.open) }
                }
                if !list.bought.isEmpty {
                    Section {
                        ForEach(list.bought) { item in
                            ItemRow(item: item) { list.toggle(item) }
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

    private func add() {
        let name = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        newItem = ""
        isAdding = true
        let wasAdded = list.add(name)
        alreadyOnList = wasAdded || name.isEmpty ? nil : name
    }

    private func remove(at offsets: IndexSet, in items: [ShoppingItem]) {
        list.remove(offsets.map { items[$0] })
    }
}

private struct ItemRow: View {
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
            }
        }
        .foregroundStyle(.primary)
        .accessibilityValue(item.checked ? "Handlad" : "")
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
