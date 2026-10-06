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

/// Felet som text för användaren. Databasens egna fel (RPC:erna) är redan på svenska.
func userMessage(for error: Error) -> String {
    if let error = error as? AuthError {
        switch error.errorCode {
        case .invalidCredentials: return "Fel e-post eller lösenord."
        case .userAlreadyExists, .emailExists: return "Det finns redan ett konto med den e-postadressen."
        case .weakPassword: return "Lösenordet är för svagt. Använd minst 6 tecken."
        case .validationFailed: return "Kontrollera e-postadressen."
        default: return error.message
        }
    }
    if let error = error as? PostgrestError { return error.message }
    if error is URLError { return "Ingen kontakt med servern. Kontrollera nätet och försök igen." }
    return error.localizedDescription
}
