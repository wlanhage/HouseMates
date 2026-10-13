import SwiftUI

/// Ett meddelande om något som just gjordes och går att ångra, t.ex. "Tog bort Mjölk".
struct UndoOffer: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

/// "Tog bort Mjölk – Ångra" längst ned i några sekunder. Ett svep nedåt stänger det.
private struct UndoBanner: View {
    let offer: UndoOffer
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(offer.message)
                .lineLimit(2)
            Spacer()
            Button("Ångra", action: undo)
                .bold()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal)
        .padding(.bottom, 8)
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
