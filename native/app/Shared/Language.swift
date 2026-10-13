import Foundation

/// Appens språk. Svenska är grundspråket; översättningarna finns i Localizable.xcstrings. Utan eget
/// val i Inställningar följer appen telefonens språk.
///
/// Vyerna översätter sig själva efter `\.locale`, som RootView sätter till språket. Text som byggs i
/// koden, som "Tog bort Mjölk", översätts med `String(appLocalized:)`.
enum AppLanguage: String, CaseIterable, Identifiable {
    case swedish = "sv"
    case english = "en"

    var id: Self { self }

    /// Där valet sparas på telefonen.
    static let storageKey = "sprak"

    /// Appen läser sitt eget val; delningstillägget har inget eget och läser appens kopia i App
    /// Group (`RecipeInbox.appGroup`).
    static var current: AppLanguage {
        AppLanguage(saved: UserDefaults.standard.string(forKey: storageKey)
            ?? UserDefaults(suiteName: RecipeInbox.appGroup)?.string(forKey: storageKey))
    }

    /// Det sparade valet, annars det första av telefonens språk som appen har, annars engelska.
    init(saved code: String?) {
        let preferred = Locale.preferredLanguages.lazy
            .compactMap { AppLanguage(rawValue: Locale(identifier: $0).language.languageCode?.identifier ?? "") }
            .first
        self = code.flatMap(AppLanguage.init(rawValue:)) ?? preferred ?? .english
    }

    /// Språket med telefonens region, så att datum på engelska blir "Fri 16 Oct" och klockan 24-timmars
    /// i Sverige.
    var locale: Locale {
        Locale(identifier: "\(rawValue)_\(Locale.current.region?.identifier ?? "SE")")
    }

    /// Språkets namn på språket självt, som i alla språkval.
    var name: String {
        switch self {
        case .swedish: "Svenska"
        case .english: "English"
        }
    }

    /// Sparar valet. Appens egna texter byter språk direkt; Apples delar, som kalenderformuläret och
    /// frågan om kalenderåtkomst, följer med nästa gång appen startar (samma inställning som iOS
    /// "Språk" för en app).
    static func choose(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: storageKey)
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        UserDefaults(suiteName: RecipeInbox.appGroup)?.set(language.rawValue, forKey: storageKey)
    }

    /// En svensk text från servern, t.ex. ett fel från en databasfunktion, på det här språket om den
    /// finns översatt. Annars visas den som den är.
    func translated(_ swedish: String) -> String {
        var resource = LocalizedStringResource(String.LocalizationValue(swedish))
        resource.locale = locale
        return String(localized: resource)
    }
}

extension String {
    /// Text på appens språk, för text som byggs i koden, som "Tog bort Mjölk". SwiftUI-vyer
    /// översätter sina egna texter.
    init(appLocalized resource: LocalizedStringResource, in language: AppLanguage = .current) {
        var resource = resource
        resource.locale = language.locale
        self.init(localized: resource)
    }
}
