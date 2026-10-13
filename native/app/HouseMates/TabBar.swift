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

/// Webbappens meny bakom plusset, som ett ark nedifrån: händelse, vara, uppgift eller städsyssla.
struct CreateMenu: View {
    enum Choice { case event, item, todo, chore }

    @Environment(\.dismiss) private var dismiss
    @Binding var chosen: Choice?

    var body: some View {
        VStack(spacing: 6) {
            row("📅", "Ny händelse", .event)
            row("🛒", "Ny vara", .item)
            row("✅", "Ny uppgift", .todo)
            row("🧽", "Ny städsyssla", .chore)
        }
        .padding(.horizontal, 14)
        .padding(.top, 26)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.surface)
    }

    private func row(_ emoji: String, _ title: String, _ choice: Choice) -> some View {
        Button {
            chosen = choice
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Text(emoji)
                    .font(.title3)
                    .frame(width: 42, height: 42)
                    .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ink)
                Spacer()
            }
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
