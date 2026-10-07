import SwiftUI

/// Visas överst i en lista när servern inte går att nå.
struct OfflineNotice: View {
    let hasPending: Bool

    var body: some View {
        Label(
            hasPending
                ? "Ingen kontakt. Dina ändringar skickas när nätet är tillbaka."
                : "Ingen kontakt. Listan visar senast hämtade läge.",
            systemImage: "wifi.slash"
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}
