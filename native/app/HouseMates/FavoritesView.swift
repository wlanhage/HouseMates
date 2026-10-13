import SwiftUI

/// Våra middagar: rätter vars ingredienser läggs på inköpslistan med ett tryck.
/// Visas som ett ark från Inköp och stängs när varorna har lagts på listan.
struct FavoritesView: View {
    @Environment(\.dismiss) private var dismiss
    let favorites: FavoriteList
    let shopping: ShoppingList
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if favorites.records.isEmpty {
                        VStack(spacing: 14) {
                            Text(verbatim: "🍽️")
                                .font(.title)
                                .frame(width: 62, height: 62)
                                .background(Color.surfaceSecondary, in: Circle())
                            Text("Inga middagar sparade än. Spara rätter ni gillar, så lägger ett tryck varorna på inköpslistan.")
                                .foregroundStyle(Color.inkMuted)
                                .multilineTextAlignment(.center)
                            Button("Lägg till den första") { isAdding = true }
                                .buttonStyle(PrimaryButtonStyle())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(28)
                        .card(cornerRadius: 18)
                    }
                    // Två kolumner med bild, som i webbappen. En rätt tas bort inifrån rätten.
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(favorites.byName) { favorite in
                            NavigationLink(value: favorite.id) {
                                FavoriteCard(favorite: favorite)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("Tips: dela en receptsida från Safari till HouseMates, så hamnar den här.")
                        .font(.footnote)
                        .foregroundStyle(Color.inkMuted)
                }
                .padding(18)
            }
            .navigationTitle("Våra middagar")
            .paperBackground()
            .navigationDestination(for: UUID.self) { id in
                FavoriteDetailView(favorites: favorites, shopping: shopping, id: id) { dismiss() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { isAdding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Ny middag")
                }
            }
            .refreshable { await favorites.sync() }
            .undoBanner(for: favorites)
            .sheet(isPresented: $isAdding) {
                FavoriteEditor(favorites: favorites, favorite: nil)
            }
            .alert("Något gick fel", isPresented: errorIsShown) {
                Button("OK") {}
            } message: {
                Text(favorites.errorMessage ?? "")
            }
        }
    }

    private var errorIsShown: Binding<Bool> {
        Binding(get: { favorites.errorMessage != nil }, set: { if !$0 { favorites.errorMessage = nil } })
    }
}

/// Rättens bild överst och namnet under, som webbappens kort.
private struct FavoriteCard: View {
    let favorite: Favorite

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DishImage(address: favorite.imageURL)
                .frame(maxWidth: .infinity)
                .frame(height: 112)
                .clipped()
            VStack(alignment: .leading, spacing: 3) {
                Text(favorite.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2, reservesSpace: true)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(Color.inkMuted)
                    .lineLimit(1)
            }
            .padding(10)
        }
        .card(cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }

    /// "8 varor · ica.se"
    private var details: String {
        [itemCountLabel(favorite.items.count), favorite.sourceURL.map(hostLabel)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

/// Rättens bild, eller en tallrik när bild saknas.
private struct DishImage: View {
    let address: String?

    var body: some View {
        AsyncImage(url: address.flatMap(URL.init(string:))) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Color.surfaceSecondary
                Text(verbatim: "🍽️").font(.title)
            }
        }
    }
}

// MARK: Rätten

private struct FavoriteDetailView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let favorites: FavoriteList
    let shopping: ShoppingList
    let id: UUID
    /// Stänger hela arket, så att man ser varorna på inköpslistan.
    let close: () -> Void

    @State private var selected: Set<String> = []
    @State private var isEditing = false
    @State private var confirmsRemoval = false

    var body: some View {
        if let favorite = favorites.favorite(id) {
            content(for: favorite)
        } else {
            ContentUnavailableView("Den här middagen finns inte längre", systemImage: "fork.knife")
        }
    }

    private func content(for favorite: Favorite) -> some View {
        List {
            if favorite.imageURL != nil {
                DishImage(address: favorite.imageURL)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .plainRow(top: 8)
            }
            HStack(spacing: 6) {
                Text(itemCountLabel(favorite.items.count))
                if let source = favorite.sourceURL, let url = URL(string: source) {
                    Text(verbatim: "·")
                    Link("Öppna på \(hostLabel(source)) ↗", destination: url)
                }
            }
            .font(.subheadline)
            .foregroundStyle(Color.inkMuted)
            .plainRow()
            if favorite.items.isEmpty {
                EmptyCard(emoji: "📝", text: "Inga varor sparade för den här rätten. Tryck på Ändra för att lägga till dem.")
            } else {
                SectionTitle("Ingredienser") {
                    Button(selected.count == Set(favorite.items).count ? "Avmarkera alla" : "Välj alla") {
                        selected = selected.count == Set(favorite.items).count ? [] : Set(favorite.items)
                    }
                    .buttonStyle(SmallButtonStyle())
                }
                .plainRow(top: 14, bottom: 2)
                Text("Bocka ur det ni redan har hemma.")
                    .font(.footnote)
                    .foregroundStyle(Color.inkMuted)
                    .plainRow(top: 0, bottom: 4)
                ForEach(Array(favorite.items.enumerated()), id: \.offset) { _, line in
                    IngredientRow(
                        line: line,
                        isSelected: selected.contains(line),
                        isOnList: isOnList(line)
                    ) { toggle(line) }
                    .cardRow()
                }
            }
            Button("Ta bort från Våra middagar", role: .destructive) { confirmsRemoval = true }
                .foregroundStyle(Color.danger)
                .frame(maxWidth: .infinity)
                .plainRow(top: 16)
        }
        .listStyle(.plain)
        .navigationTitle(favorite.name)
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Ändra") { isEditing = true }
        }
        .safeAreaInset(edge: .bottom) {
            if !favorite.items.isEmpty {
                Button {
                    shopping.add(ingredients: favorite.items.filter(selected.contains), by: session.me?.id)
                    close()
                } label: {
                    Text(selected.isEmpty ? "Välj varor att lägga till" : "Lägg \(itemCountLabel(selected.count)) på listan")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selected.isEmpty)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
            }
        }
        // Förval: allt utom det som redan står på listan. Görs om när rätten ändras.
        .onChange(of: favorite.items, initial: true) { _, items in
            selected = Set(items.filter { !isOnList($0) })
        }
        .sheet(isPresented: $isEditing) {
            FavoriteEditor(favorites: favorites, favorite: favorite)
        }
        .confirmationDialog("Ta bort \(favorite.name)?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("Ta bort", role: .destructive) {
                favorites.remove(favorite)
                dismiss()
            }
        }
    }

    private func isOnList(_ line: String) -> Bool {
        shopping.isOnList(Ingredient(line: line).name)
    }

    private func toggle(_ line: String) {
        if selected.contains(line) {
            selected.remove(line)
        } else {
            selected.insert(line)
        }
    }
}

private struct IngredientRow: View {
    let line: String
    let isSelected: Bool
    let isOnList: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                CheckMark(isOn: isSelected)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(line)
                        .foregroundStyle(isOnList && !isSelected ? Color.inkMuted : Color.ink)
                    if isOnList {
                        Text("Finns redan på listan")
                            .font(.caption)
                            .foregroundStyle(Color.inkMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: Ny eller ändrad rätt

private struct FavoriteEditor: View {
    @Environment(\.dismiss) private var dismiss
    let favorites: FavoriteList
    let favorite: Favorite?

    @State private var link = ""
    @State private var isFetching = false
    @State private var name = ""
    @State private var itemsText = ""
    @State private var imageURL: String?
    @State private var sourceURL: String?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                if favorite == nil {
                    Section {
                        HStack {
                            TextField("Klistra in länken", text: $link)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit(fetch)
                            if isFetching {
                                ProgressView()
                            } else {
                                Button("Hämta", action: fetch)
                                    .disabled(trimmedLink.isEmpty)
                            }
                        }
                        if let sourceURL {
                            HStack(spacing: 12) {
                                if imageURL != nil {
                                    DishImage(address: imageURL)
                                        .frame(width: 48, height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                Text("Från \(hostLabel(sourceURL))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Från en receptsida")
                    } footer: {
                        Text("Du kan också dela en receptsida från Safari till HouseMates.")
                    }
                }
                Section("Rätt") {
                    TextField("T.ex. tacos", text: $name)
                }
                Section {
                    TextEditor(text: $itemsText)
                        .frame(minHeight: 180)
                        .accessibilityLabel("Ingredienser")
                        .overlay(alignment: .topLeading) {
                            if itemsText.isEmpty {
                                Text("500 g köttfärs\nTortillas\nSalsa")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("Ingredienser, en per rad")
                } footer: {
                    if !items.isEmpty {
                        Text(itemCountLabel(items.count))
                    }
                }
            }
            .navigationTitle(favorite == nil ? "Ny middag" : "Ändra middag")
            .paperBackground()
            // Ett svep nedåt ska inte kasta en lång ingredienslista; Avbryt gör det med flit.
            .interactiveDismissDisabled(hasChanges)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara", action: save)
                        .disabled(trimmedName.isEmpty || items.isEmpty)
                }
            }
            .alert(message ?? "", isPresented: messageIsShown) {
                Button("OK") {}
            }
            .onAppear(perform: load)
        }
    }

    private var trimmedLink: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Något har skrivits eller ändrats sedan arket öppnades.
    private var hasChanges: Bool {
        guard let favorite else { return !name.isEmpty || !itemsText.isEmpty }
        return name != favorite.name || itemsText != favorite.items.joined(separator: "\n")
    }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var items: [String] { Favorite.items(from: itemsText) }

    private var messageIsShown: Binding<Bool> {
        Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    }

    private func load() {
        guard let favorite else { return }
        name = favorite.name
        itemsText = favorite.items.joined(separator: "\n")
    }

    private func fetch() {
        guard !trimmedLink.isEmpty, !isFetching else { return }
        isFetching = true
        Task {
            defer { isFetching = false }
            do {
                let recipe = try await RecipeImport.fetch(trimmedLink)
                name = recipe.name
                itemsText = recipe.items.joined(separator: "\n")
                imageURL = recipe.imageURL
                sourceURL = recipe.sourceURL
                if recipe.items.isEmpty {
                    message = String(appLocalized: "Hittade inga ingredienser. Fyll i dem själv.")
                }
            } catch {
                message = userMessage(for: error)
            }
        }
    }

    private func save() {
        if let favorite {
            favorites.update(favorite, name: trimmedName, items: items)
        } else if let sourceURL, favorites.contains(sourceURL: sourceURL) {
            message = String(appLocalized: "Det receptet finns redan sparat.")
            return
        } else {
            favorites.add(name: trimmedName, items: items, imageURL: imageURL, sourceURL: sourceURL)
        }
        dismiss()
    }
}
