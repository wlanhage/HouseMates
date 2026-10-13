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
    @FocusState private var focus: Field?

    private enum Field { case name, email, password }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    LoginLogo()
                        .padding(.top, 44)
                        .padding(.bottom, 18)
                    PillTabs(selection: mode, options: [(false, "Logga in"), (true, "Skapa konto")])
                        .padding(.bottom, 6)
                    if isCreatingAccount {
                        LabeledField("Ditt namn") {
                            TextField("Förnamn", text: $name)
                                .textContentType(.givenName)
                                .focused($focus, equals: .name)
                                .paperField(isFocused: focus == .name)
                        }
                    }
                    LabeledField("E-post") {
                        // verbatim: annars blir exemplet en blå e-postlänk.
                        TextField(text: $email, prompt: Text(verbatim: "namn@exempel.se")) { Text("E-post") }
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .email)
                            .paperField(isFocused: focus == .email)
                    }
                    LabeledField("Lösenord") {
                        SecureField("Lösenord", text: $password)
                            .textContentType(isCreatingAccount ? .newPassword : .password)
                            .submitLabel(.go)
                            .onSubmit { if canSubmit { Task { await submit() } } }
                            .focused($focus, equals: .password)
                            .paperField(isFocused: focus == .password)
                    }
                    message
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack(spacing: 10) {
                            Text(isCreatingAccount ? "Skapa konto" : "Logga in")
                            if isWorking {
                                ProgressView().tint(Color.onAccent)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSubmit || isWorking)
                    .padding(.top, 4)
                    if isCreatingAccount {
                        NavigationLink("Så hanterar vi dina uppgifter") { PolicyView() }
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Button("Glömt lösenordet?") { isResettingPassword = true }
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
            .background(LoginBackground())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isResettingPassword) {
                ForgotPasswordView(email: trimmedEmail)
            }
        }
    }

    @ViewBuilder
    private var message: some View {
        if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(Color.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let notice {
            Text(notice)
                .foregroundStyle(Color.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if isCreatingAccount {
            Text("Minst 8 tecken. Ditt namn syns för din partner.")
                .foregroundStyle(Color.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
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

    @FocusState private var codeIsFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Hej \(session.me?.name ?? "")! 👋")
                        .font(.title.weight(.heavy))
                        .foregroundStyle(Color.ink)
                        .padding(.top, 24)
                    Text("Ett hushåll delar listor, middagar och kalender. Den ena skapar hushållet och skickar koden till den andra.")
                        .foregroundStyle(Color.inkMuted)
                    VStack(alignment: .leading, spacing: 10) {
                        FieldLabel("Ny här?")
                        Button { Task { await run { try await session.createHousehold() } } } label: {
                            Text("Skapa hushåll").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(16)
                    .card(cornerRadius: 18)
                    VStack(alignment: .leading, spacing: 10) {
                        FieldLabel("Har du fått en kod?")
                        TextField("Kod, t.ex. K7M2QXPA", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($codeIsFocused)
                            .paperField(isFocused: codeIsFocused)
                        Button { Task { await run { try await session.joinHousehold(code: code) } } } label: {
                            Text("Gå med").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(code.trimmingCharacters(in: .whitespaces).count != 8)
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(Color.danger)
                        }
                    }
                    .padding(16)
                    .card(cornerRadius: 18)
                    HStack {
                        Button("Logga ut") { Task { await session.signOut() } }
                            .foregroundStyle(Color.danger)
                        Spacer()
                        DeleteAccountButton()
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
            }
            .background(Color.paper)
            .disabled(isWorking)
            .toolbar(.hidden, for: .navigationBar)
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

/// Webbappens inloggningslogga: era två prickar, namnet och undertiteln.
private struct LoginLogo: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: -12) {
                dot(Color(hex: "#D4537E"))
                dot(Color(hex: "#378ADD"))
            }
            .accessibilityHidden(true)
            Text("HouseMates")
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(Color.ink)
            Text("Er gemensamma planering")
                .foregroundStyle(Color.inkMuted)
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 30, height: 30)
            .overlay { Circle().strokeBorder(Color.paper, lineWidth: 4) }
    }
}

/// Papperet med en rosa och en blå dimma i hörnen, som webbappens inloggning.
private struct LoginBackground: View {
    var body: some View {
        ZStack {
            Color.paper
            GeometryReader { geometry in
                let size = max(geometry.size.width, geometry.size.height) * 0.42
                Circle()
                    .fill(Color(hex: "#D4537E"))
                    .frame(width: size, height: size)
                    .position(x: size * 0.15, y: size * 0.1)
                Circle()
                    .fill(Color(hex: "#378ADD"))
                    .frame(width: size, height: size)
                    .position(x: geometry.size.width - size * 0.15, y: geometry.size.height - size * 0.1)
            }
            .blur(radius: 70)
            .opacity(0.16)
        }
        .ignoresSafeArea()
    }
}

/// Etikett över ett fält, som i webbappens formulär.
private struct LabeledField<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(label)
            content
        }
    }
}

