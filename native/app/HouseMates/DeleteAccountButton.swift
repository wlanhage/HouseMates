import SwiftUI

/// Radera konto. Finns både i Inställningar och innan man har ett hushåll, så att raderingen
/// alltid går att hitta (App Review 5.1.1(v)).
struct DeleteAccountButton: View {
    @Environment(AppSession.self) private var session
    @State private var isConfirming = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        Button("Radera konto", role: .destructive) { isConfirming = true }
            .disabled(isDeleting)
            .alert("Radera kontot?", isPresented: $isConfirming) {
                Button("Radera", role: .destructive) { Task { await delete() } }
                Button("Avbryt", role: .cancel) {}
            } message: {
                Text(consequences)
            }
            .alert("Kunde inte radera kontot", isPresented: errorIsShown) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
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

    private var errorIsShown: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func delete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await session.deleteAccount()
        } catch {
            errorMessage = userMessage(for: error)
        }
    }
}
