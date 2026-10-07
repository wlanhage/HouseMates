import SwiftUI

struct ForgotPasswordView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State var email: String
    @State private var sentTo: String?
    @State private var errorMessage: String?
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            Form {
                if let sentTo {
                    Section {
                        Text("Om det finns ett konto för \(sentTo) har vi skickat en länk dit. Öppna mejlet på den här telefonen och tryck på länken för att välja ett nytt lösenord.")
                    }
                } else {
                    Section {
                        TextField("E-post", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } footer: {
                        if let errorMessage {
                            Text(errorMessage).foregroundStyle(.red)
                        } else {
                            Text("Vi skickar en länk där du väljer ett nytt lösenord.")
                        }
                    }
                    Button("Skicka länk") { Task { await send() } }
                        .disabled(email.isEmpty || isSending)
                }
            }
            .navigationTitle("Glömt lösenordet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sentTo == nil ? "Avbryt" : "Klar") { dismiss() }
                }
            }
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            let address = email.trimmingCharacters(in: .whitespaces)
            try await session.requestPasswordReset(email: address)
            sentTo = address
        } catch {
            errorMessage = userMessage(for: error)
        }
    }
}

struct NewPasswordView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Nytt lösenord", text: $password)
                        .textContentType(.newPassword)
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else {
                        Text("Minst 6 tecken.")
                    }
                }
            }
            .navigationTitle("Nytt lösenord")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara") { Task { await save() } }
                        .disabled(password.count < 6 || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await session.setNewPassword(password)
            dismiss()
        } catch {
            errorMessage = userMessage(for: error)
        }
    }
}
