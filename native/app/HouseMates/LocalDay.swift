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

    /// "Idag", "Imorgon", "Igår" eller "ons 9 okt".
    static func label(_ day: String, from today: Date = .now) -> String {
        switch days(until: day, from: today) {
        case 0: return "Idag"
        case 1: return "Imorgon"
        case -1: return "Igår"
        default:
            guard let date = date(from: day) else { return day }
            return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "sv_SE")))
        }
    }
}
