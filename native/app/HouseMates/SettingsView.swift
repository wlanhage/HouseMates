import SwiftUI

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let calendar: SharedCalendar
    @State private var changesPassword = false
    @AppStorage(AppLanguage.storageKey) private var savedLanguage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Du", value: session.me?.name ?? "")
                    if let partner = session.partner {
                        LabeledContent("Din partner", value: partner.name)
                    } else if let code = session.household?.inviteCode {
                        LabeledContent("Inbjudningskod", value: code)
                        ShareLink("Bjud in din partner", item: String(appLocalized: "Gå med i vårt hushåll i HouseMates med koden \(code)"))
                    }
                    ConfirmedActionButton(
                        title: "Lämna hushållet",
                        question: "Lämna hushållet?",
                        consequences: leaveConsequences,
                        confirmLabel: "Lämna"
                    ) {
                        try await session.leaveHousehold()
                    }
                } header: {
                    SectionTitle("Hushåll")
                }
                Section {
                    LabeledContent("Delad kalender") {
                        if let title = calendar.linkedCalendar?.title {
                            Text(title)
                        } else {
                            Text("Inte vald")
                        }
                    }
                } header: {
                    SectionTitle("Kalender")
                }
                NotificationSection()
                Section {
                    Picker("Språk", selection: language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(verbatim: language.name).tag(language)
                        }
                    }
                } header: {
                    SectionTitle("Språk")
                } footer: {
                    if AppLanguage(saved: savedLanguage) != .swedish {
                        Text("Notiser och mejl är än så länge på svenska.")
                    }
                }
                Section {
                    Button("Byt lösenord") { changesPassword = true }
                    Button("Logga ut", role: .destructive) { Task { await session.signOut() } }
                        .foregroundStyle(Color.danger)
                } header: {
                    SectionTitle("Konto")
                }
                AboutSection()
                Section {
                    DeleteAccountButton()
                }
            }
            .navigationTitle("Inställningar")
            .paperBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") { dismiss() }
                }
            }
            .refreshable { await session.reload() }
            .sheet(isPresented: $changesPassword) { NewPasswordView() }
        }
    }

    private var language: Binding<AppLanguage> {
        Binding(get: { AppLanguage(saved: savedLanguage) }, set: { AppLanguage.choose($0) })
    }

    private var leaveConsequences: LocalizedStringKey {
        guard let partner = session.partner else {
            return "Du är ensam i hushållet, så hushållet med listor och middagar raderas. Sedan kan du skapa ett nytt hushåll eller gå med i ett annat."
        }
        return "Listorna och middagarna blir kvar för \(partner.name). Sedan kan du skapa ett nytt hushåll eller gå med i ett annat. Kalendern ni delar i Apple Kalender påverkas inte; sluta dela den i Kalender-appen om du vill."
    }
}

/// Kugghjulet uppe till höger på flikarna, som i webbappen.
struct SettingsButton: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Button { session.showsSettings = true } label: {
            IconButtonLabel(systemImage: "gearshape")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Inställningar")
    }
}
