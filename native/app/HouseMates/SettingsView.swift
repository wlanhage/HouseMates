import SwiftUI

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.openURL) private var openURL
    let calendar: SharedCalendar
    private let push = Push.shared

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
                Section("Notiser") {
                    switch push.authorization {
                    case .authorized, .provisional, .ephemeral:
                        LabeledContent("Notiser", value: "På")
                    case .denied:
                        Button("Slå på notiser i Inställningar") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        }
                    default:
                        Button("Slå på notiser") { Task { await push.requestPermission() } }
                    }
                }
                Section {
                    Button("Logga ut", role: .destructive) { Task { await session.signOut() } }
                }
                Section {
                    DeleteAccountButton()
                }
            }
            .navigationTitle("Inställningar")
            .refreshable { await session.reload() }
            .task { await push.refreshAuthorization() }
        }
    }

    private var leaveConsequences: String {
        guard let partner = session.partner else {
            return "Du är ensam i hushållet, så hushållet och inköpslistan raderas. Sedan kan du skapa ett nytt hushåll eller gå med i ett annat."
        }
        return "Inköpslistan blir kvar för \(partner.name). Sedan kan du skapa ett nytt hushåll eller gå med i ett annat. Kalendern ni delar i Apple Kalender påverkas inte; sluta dela den i Kalender-appen om du vill."
    }
}
