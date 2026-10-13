import SwiftUI

/// Webbappens flytande flikrad: Hem, Kalender, ett runt grönt plus, Inköp och Att göra. Vald flik
/// får din färg. Ersätter iOS egen flikrad, som saknar en knapp i mitten.
struct TabBar: View {
    @Environment(AppSession.self) private var session
    @Binding var selection: AppTab
    let create: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            item(.home, title: "Hem", systemImage: "house")
            item(.calendar, title: "Kalender", systemImage: "calendar")
            createButton
            item(.shopping, title: "Inköp", systemImage: "cart")
            item(.todos, title: "Att göra", systemImage: "checkmark.square")
        }
        .frame(height: 62)
        // Formen ligger i bakgrunden, så att plusset kan sticka upp ovanför raden.
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.surface.opacity(0.88))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.hairline)
                }
                .shadow(color: .black.opacity(0.14), radius: 9, y: 8)
                .shadow(color: .black.opacity(0.12), radius: 22, y: 20)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var myColor: Color { session.color(for: session.me?.id) }

    private func item(_ tab: AppTab, title: String, systemImage: String) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .frame(height: 24)
                Text(title)
                    .font(.system(size: 10.5, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? myColor : Color.inkMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(myColor.opacity(0.1))
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var createButton: some View {
        Button(action: create) {
            Image(systemName: "plus")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(Color.onAccent)
                .frame(width: 60, height: 60)
                .background(
                    LinearGradient(colors: [Color.accent.opacity(0.8), Color.accent], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Circle()
                )
                .shadow(color: Color.accent.opacity(0.45), radius: 12, y: 10)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
        }
        .buttonStyle(.plain)
        .offset(y: -20)
        .frame(width: 76)
        .accessibilityLabel("Lägg till")
    }
}
