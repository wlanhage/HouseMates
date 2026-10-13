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
                Picker("Konto", selection: mode) {
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
                        .submitLabel(.go)
                        .onSubmit { if canSubmit { Task { await submit() } } }
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else if let notice {
                        Text(notice)
                    } else if isCreatingAccount {
                        Text("Minst 8 tecken. Ditt namn syns för din partner.")
                    }
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Text(isCreatingAccount ? "Skapa konto" : "Logga in")
                        if isWorking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!canSubmit || isWorking)

                if isCreatingAccount {
                    Section {
                        NavigationLink("Så hanterar vi dina uppgifter") { PolicyView() }
                    }
                } else {
                    Button("Glömt lösenordet?") { isResettingPassword = true }
                        .font(.subheadline)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("HouseMates")
            .paperBackground()
            .sheet(isPresented: $isResettingPassword) {
                ForgotPasswordView(email: trimmedEmail)
            }
        }
    }

    /// Byte mellan att logga in och skapa konto tar bort meddelanden som gällde det andra läget.
    private var mode: Binding<Bool> {
        Binding(get: { isCreatingAccount }, set: {
            isCreatingAccount = $0
            errorMessage = nil
            notice = nil
        })
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSubmit: Bool {
        guard !trimmedEmail.isEmpty, !password.isEmpty else { return false }
        // Längdkravet gäller nya lösenord; ett äldre kortare lösenord ska fortfarande gå att logga in med.
        return !isCreatingAccount || (password.count >= 8 && !trimmedName.isEmpty)
    }

    private func submit() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        notice = nil
        do {
            if isCreatingAccount {
                if try await session.signUp(name: trimmedName, email: trimmedEmail, password: password) {
                    isCreatingAccount = false
                    notice = "Vi har skickat ett mejl till \(trimmedEmail). Bekräfta adressen och logga sedan in."
                }
            } else {
                try await session.signIn(email: trimmedEmail, password: password)
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
                    Text("Ett hushåll delar listor, middagar och kalender. Den ena skapar hushållet och skickar koden till den andra.")
                }
                Section("Ny här?") {
                    Button("Skapa hushåll") { Task { await run { try await session.createHousehold() } } }
                }
                Section {
                    TextField("Kod, t.ex. K7M2QXPA", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Gå med") { Task { await run { try await session.joinHousehold(code: code) } } }
                        .disabled(code.trimmingCharacters(in: .whitespaces).count != 8)
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
            .paperBackground()
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
