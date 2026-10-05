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
            }
            .navigationTitle("Inställningar")
            .refreshable { await session.reload() }
            .task { await push.refreshAuthorization() }
        }
    }
}
