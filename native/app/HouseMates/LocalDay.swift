import Foundation

/// Rena datum ("2026-10-09") som databasens `date`-kolumner. Räknas alltid i telefonens
/// tidszon och görs aldrig om till midnatt i UTC, så att en dag inte kan glida till dagen före.
enum LocalDay {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Följer telefonens tidszon även om den byts medan appen är igång.
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from day: String) -> Date? {
        formatter.date(from: day)
    }

    static func adding(_ days: Int, to day: String) -> String? {
        date(from: day)
            .flatMap { Calendar.current.date(byAdding: .day, value: days, to: $0) }
            .map(string(from:))
    }

    /// Hur många dagar det är från `today` till `day`: 0 idag, 1 imorgon, -1 igår.
    static func days(until day: String, from today: Date = .now) -> Int? {
        guard let target = date(from: day) else { return nil }
        let start = Calendar.current.startOfDay(for: today)
        return Calendar.current.dateComponents([.day], from: start, to: target).day
    }

    /// "Idag", "Imorgon", "Igår" eller "ons 9 okt" ("Wed 9 Oct" på engelska).
    static func label(_ day: String, from today: Date = .now, in language: AppLanguage = .current) -> String {
        switch days(until: day, from: today) {
        case 0: return String(appLocalized: "Idag", in: language)
        case 1: return String(appLocalized: "Imorgon", in: language)
        case -1: return String(appLocalized: "Igår", in: language)
        default:
            guard let date = date(from: day) else { return day }
            return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(language.locale))
                .replacingOccurrences(of: ".", with: "")
        }
    }

    /// En period, som "fre 10 okt–sön 12 okt" eller "idag–imorgon". Svenskan skriver den andra
    /// dagen med liten bokstav, som mitt i en mening; engelskan behåller stor.
    static func period(from start: String, to end: String, today: Date = .now, in language: AppLanguage = .current) -> String {
        let last = label(end, from: today, in: language)
        return "\(label(start, from: today, in: language))–\(language == .swedish ? last.lowercased() : last)"
    }
}
