import SwiftUI

struct ShoppingView: View {
    @Environment(AppSession.self) private var session
    let list: ShoppingList
    @State private var newItem = ""
    @FocusState private var isAdding: Bool
    @AppStorage("notiskort-dolt") private var hidesNotificationCard = false
    private let push = Push.shared

    var body: some View {
        NavigationStack {
            List {
                if list.isOffline {
                    Label(
                        list.pending.isEmpty
                            ? "Ingen kontakt. Listan visar senast hämtade läge."
                            : "Ingen kontakt. Dina ändringar skickas när nätet är tillbaka.",
                        systemImage: "wifi.slash"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                            Button("Töm") { list.clearBought() }
                                .font(.subheadline)
                        }
                    }
                }
            }
            .navigationTitle("Inköp")
            .refreshable { await list.sync() }
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
        let name = newItem
        newItem = ""
        isAdding = true
        list.add(name)
    }

    private func remove(at offsets: IndexSet, in items: [ShoppingItem]) {
        for item in offsets.map({ items[$0] }) {
            list.remove(item)
        }
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
                Text(item.name)
                    .strikethrough(item.checked)
                    .foregroundStyle(item.checked ? .secondary : .primary)
            }
        }
        .foregroundStyle(.primary)
    }
}

private struct NotificationCard: View {
    let partnerName: String?
    let dismiss: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Få en notis när \(partnerName ?? "din partner") lägger till varor eller nya händelser i kalendern.")
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
