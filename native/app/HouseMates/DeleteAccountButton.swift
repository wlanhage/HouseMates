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

    private var consequences: LocalizedStringKey {
        guard session.household != nil else {
            return "Ditt konto och ditt namn raderas. Det går inte att ångra."
        }
        guard let partner = session.partner else {
            return "Ditt konto, ditt namn och din historik raderas. Hushållets listor och middagar raderas också. Kalendern i Apple Kalender påverkas inte. Det går inte att ångra."
        }
        return "Ditt konto, ditt namn och din historik raderas. Listorna och middagarna finns kvar för \(partner.name). Kalendern i Apple Kalender påverkas inte. Det går inte att ångra."
    }
}
