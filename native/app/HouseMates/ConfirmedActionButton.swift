import SwiftUI

/// Knapp för något som inte går att ångra: frågar först och visar felet om det inte gick.
struct ConfirmedActionButton: View {
    let title: LocalizedStringKey
    let question: LocalizedStringKey
    let consequences: LocalizedStringKey
    let confirmLabel: LocalizedStringKey
    let action: () async throws -> Void

    @State private var isConfirming = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Button(title, role: .destructive) { isConfirming = true }
            .foregroundStyle(Color.danger)
            .disabled(isWorking)
            .alert(question, isPresented: $isConfirming) {
                Button(confirmLabel, role: .destructive) { Task { await run() } }
                Button("Avbryt", role: .cancel) {}
            } message: {
                Text(consequences)
            }
            .alert("Något gick fel", isPresented: errorIsShown) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private var errorIsShown: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func run() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await action()
        } catch {
            errorMessage = userMessage(for: error)
        }
    }
}
