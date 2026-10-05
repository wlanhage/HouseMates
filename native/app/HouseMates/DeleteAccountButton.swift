import SwiftUI

/// Radera konto. Finns både i Inställningar och innan man har ett hushåll, så att raderingen
/// alltid går att hitta (App Review 5.1.1(v)).
struct DeleteAccountButton: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        ConfirmedActionButton(
            title: "Radera konto",
            question: "Radera kontot?",
            consequences: consequences,
            confirmLabel: "Radera"
        ) {
            try await session.deleteAccount()
        }
    }

    private var consequences: String {
        guard session.household != nil else {
            return "Ditt konto och ditt namn raderas. Det går inte att ångra."
        }
        let household = session.partner.map { "Inköpslistan finns kvar för \($0.name)." }
            ?? "Hushållets inköpslista raderas också."
        return "Ditt konto, ditt namn och din historik raderas. \(household) Kalendern i Apple Kalender påverkas inte. Det går inte att ångra."
    }
}
