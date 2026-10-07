import SwiftUI

struct AuthView: View {
    @Environment(AppSession.self) private var session
    @State private var isCreatingAccount = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var isWorking = false
    @State private var isResettingPassword = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Konto", selection: $isCreatingAccount) {
                    Text("Logga in").tag(false)
                    Text("Skapa konto").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                Section {
                    if isCreatingAccount {
                        TextField("Ditt namn", text: $name)
                            .textContentType(.givenName)
                    }
                    TextField("E-post", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Lösenord", text: $password)
                        .textContentType(isCreatingAccount ? .newPassword : .password)
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else if let notice {
                        Text(notice)
                    } else if isCreatingAccount {
                        Text("Minst 6 tecken. Ditt namn syns för din partner.")
                    }
                }

                Button(isCreatingAccount ? "Skapa konto" : "Logga in") {
                    Task { await submit() }
                }
                .disabled(!canSubmit || isWorking)

                if !isCreatingAccount {
                    Button("Glömt lösenordet?") { isResettingPassword = true }
                        .font(.subheadline)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("HouseMates")
            .sheet(isPresented: $isResettingPassword) {
                ForgotPasswordView(email: email)
            }
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var canSubmit: Bool {
        !email.isEmpty && password.count >= 6 && (!isCreatingAccount || !trimmedName.isEmpty)
    }

    private func submit() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            if isCreatingAccount {
                if try await session.signUp(name: trimmedName, email: email, password: password) {
                    isCreatingAccount = false
                    notice = "Vi har skickat ett mejl till \(email). Bekräfta adressen och logga sedan in."
                }
            } else {
                try await session.signIn(email: email, password: password)
            }
        } catch {
            errorMessage = userMessage(for: error)
        }
    }
}

struct HouseholdSetupView: View {
    @Environment(AppSession.self) private var session
    @State private var code = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Ett hushåll delar inköpslista och kalender. Den ena skapar hushållet och skickar koden till den andra.")
                }
                Section("Ny här?") {
                    Button("Skapa hushåll") { Task { await run { try await session.createHousehold() } } }
                }
                Section {
                    TextField("Kod, t.ex. K7M2QX", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Gå med") { Task { await run { try await session.joinHousehold(code: code) } } }
                        .disabled(code.trimmingCharacters(in: .whitespaces).count != 6)
                } header: {
                    Text("Har du fått en kod?")
                } footer: {
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                }
                Section {
                    Button("Logga ut", role: .destructive) { Task { await session.signOut() } }
                    DeleteAccountButton()
                }
            }
            .disabled(isWorking)
            .navigationTitle("Hej \(session.me?.name ?? "")!")
        }
    }

    private func run(_ action: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await action()
        } catch {
            errorMessage = userMessage(for: error)
        }
    }
}
