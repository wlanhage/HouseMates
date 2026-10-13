import Foundation
import Supabase

/// Den enda Supabase-klienten. Adress och nyckel kommer från Config/*.xcconfig via Info.plist.
enum Backend {
    static let client: SupabaseClient = {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let address = info["SupabaseURL"] as? String, let url = URL(string: address),
              let key = info["SupabaseKey"] as? String, !key.isEmpty else {
            fatalError("SupabaseURL och SupabaseKey saknas i Info.plist (se Config/Local.xcconfig)")
        }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true),
                global: .init(session: session)
            )
        )
    }()

    /// Kortare väntan än standardens 60 s: med svag täckning ska appen snabbt gå över till att
    /// spara ändringarna lokalt och försöka igen.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()
}

/// Ett fel vars text redan är skriven för användaren.
struct UserFacingError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Felet som text för användaren, på appens språk. Text från servern visas bara när den kommer
/// från våra egna funktioner; den är skriven på svenska och översätts om den finns i
/// Localizable.xcstrings. Allt annat får en egen text här.
func userMessage(for error: Error) -> String {
    if let error = error as? UserFacingError { return error.message }
    if let error = error as? AuthError { return String(appLocalized: authMessage(for: error)) }
    if let error = error as? PostgrestError, error.code == "P0001" { return AppLanguage.current.translated(error.message) }
    if case let FunctionsError.httpError(_, data) = error,
       let reply = try? JSONDecoder().decode(FunctionErrorReply.self, from: data) {
        return AppLanguage.current.translated(reply.error.message)
    }
    if error is URLError { return String(appLocalized: "Ingen kontakt med servern. Kontrollera nätet och försök igen.") }
    return String(appLocalized: "Något gick fel. Försök igen.")
}

private func authMessage(for error: AuthError) -> LocalizedStringResource {
    if case .sessionMissing = error { return "Logga in igen." }
    switch error.errorCode {
    case .invalidCredentials: return "Fel e-post eller lösenord."
    case .emailNotConfirmed: return "Bekräfta din e-postadress först. Länken finns i mejlet vi skickade."
    case .userAlreadyExists, .emailExists: return "Det finns redan ett konto med den e-postadressen."
    case .weakPassword: return "Lösenordet är för svagt. Använd minst 8 tecken."
    case .samePassword: return "Välj ett annat lösenord än det du har nu."
    case .validationFailed: return "Kontrollera e-postadressen."
    case .overEmailSendRateLimit, .overRequestRateLimit: return "För många försök just nu. Vänta en stund och försök igen."
    case .flowStateExpired, .flowStateNotFound, .otpExpired, .badCodeVerifier:
        return "Länken har gått ut eller redan använts. Be om en ny."
    case .sessionNotFound, .sessionExpired, .refreshTokenNotFound, .refreshTokenAlreadyUsed:
        return "Logga in igen."
    default: return "Inloggningen fungerade inte. Försök igen."
    }
}

/// Våra edge functions svarar med `{ "error": { "message": "…" } }` på svenska.
struct FunctionErrorReply: Decodable {
    struct Detail: Decodable { let message: String }
    let error: Detail
}
