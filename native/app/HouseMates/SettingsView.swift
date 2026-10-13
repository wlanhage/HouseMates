import SwiftUI

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let calendar: SharedCalendar
    @State private var changesPassword = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Hushåll") {
                    LabeledContent("Du", value: session.me?.name ?? "")
                    if let partner = session.partner {
                        LabeledContent("Din partner", value: partner.name)
                    } else if let code = session.household?.inviteCode {
                        LabeledContent("Inbjudningskod", value: code)
                        ShareLink("Bjud in din partner", item: "Gå med i vårt hushåll i HouseMates med koden \(code)")
                    }
                    ConfirmedActionButton(
                        title: "Lämna hushållet",
                        question: "Lämna hushållet?",
                        consequences: leaveConsequences,
                        confirmLabel: "Lämna"
                    ) {
                        try await session.leaveHousehold()
                    }
                }
                Section("Kalender") {
                    LabeledContent("Delad kalender", value: calendar.linkedCalendar?.title ?? "Inte vald")
                }
                NotificationSection()
                Section("Konto") {
                    Button("Byt lösenord") { changesPassword = true }
                    Button("Logga ut", role: .destructive) { Task { await session.signOut() } }
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

    private var leaveConsequences: String {
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
        Button("Inställningar", systemImage: "gearshape") { session.showsSettings = true }
    }
}
