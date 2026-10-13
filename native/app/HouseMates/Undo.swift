import SwiftUI

/// Ett meddelande om något som just gjordes och går att ångra, t.ex. "Tog bort Mjölk".
struct UndoOffer: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

/// "Tog bort Mjölk · Ångra" som en mörk kapsel längst ned i några sekunder, som i webbappen.
/// Ett svep nedåt stänger den.
private struct UndoBanner: View {
    let offer: UndoOffer
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(offer.message)
                .lineLimit(2)
            Button("Ångra", action: undo)
                .fontWeight(.heavy)
                .foregroundStyle(Color(hex: "#8FD3B8"))
        }
        .font(.subheadline)
        .foregroundStyle(Color(hex: "#F2EFE9"))
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .background(Color(hex: "#2B2926"), in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
        .gesture(DragGesture(minimumDistance: 10).onEnded { if $0.translation.height > 20 { dismiss() } })
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear { AccessibilityNotification.Announcement(offer.message).post() }
    }
}

extension View {
    /// Visar tabellens ångra-meddelande längst ned i vyn.
    func undoBanner<Change: TableChange>(for table: SyncedTable<Change>) -> some View {
        safeAreaInset(edge: .bottom) {
            if let offer = table.undo {
                UndoBanner(offer: offer, undo: table.performUndo, dismiss: table.dismissUndo)
            }
        }
        .animation(.default, value: table.undo)
    }
}
