import SwiftUI

/// Visas överst i en lista när servern inte går att nå, som webbappens gula rad.
struct OfflineNotice: View {
    let hasPending: Bool

    var body: some View {
        Label(
            hasPending
                ? "Ingen kontakt. Dina ändringar skickas när nätet är tillbaka."
                : "Ingen kontakt. Listan visar senast hämtade läge.",
            systemImage: "wifi.slash"
        )
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Color.warningText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.warningBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .plainRow()
    }
}
