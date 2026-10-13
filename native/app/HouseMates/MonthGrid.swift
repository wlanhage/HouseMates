import Foundation

/// Månadsrutnätet i kalendern. Veckan börjar på måndag. Samma regler som webbappens monthGrid.ts.
struct MonthGrid: Equatable {
    let year: Int
    let month: Int          // 1–12
    /// Dagarna som "2026-09-01"; nil är utfyllnad före den 1:a.
    let days: [String?]
    let title: String       // "September 2026"
    let language: AppLanguage

    /// Veckodagarna överst i rutnätet, måndag först.
    static func weekdays(in language: AppLanguage = .current) -> [String] {
        switch language {
        case .swedish: ["mån", "tis", "ons", "tor", "fre", "lör", "sön"]
        case .english: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        }
    }

    init(year: Int, month: Int, language: AppLanguage = .current) {
        let calendar = Calendar(identifier: .gregorian)
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let dayCount = calendar.range(of: .day, in: .month, for: first)!.count
        // Calendar räknar söndag som 1; här är måndag 0.
        let leading = (calendar.component(.weekday, from: first) + 5) % 7
        self.year = year
        self.month = month
        self.language = language
        days = Array(repeating: nil, count: leading)
            + (1...dayCount).map { String(format: "%04d-%02d-%02d", year, month, $0) }
        let label = first.formatted(.dateTime.month(.wide).year().locale(language.locale))
        title = label.prefix(1).uppercased() + label.dropFirst()
    }

    /// Månaden som dagen ("2026-09-07") ligger i.
    init(containing day: String, language: AppLanguage = .current) {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        self.init(year: parts[0], month: parts[1], language: language)
    }

    /// Dagarna vecka för vecka; sista veckan fylls ut till sju.
    var weeks: [[String?]] {
        let padded = days + Array(repeating: nil, count: (7 - days.count % 7) % 7)
        return stride(from: 0, to: padded.count, by: 7).map { Array(padded[$0..<$0 + 7]) }
    }

    var first: String { days.compactMap { $0 }.first! }
    var last: String { days.compactMap { $0 }.last! }

    func contains(_ day: String) -> Bool { day >= first && day <= last }

    func adding(months: Int) -> MonthGrid {
        let index = year * 12 + (month - 1) + months
        return MonthGrid(year: index / 12, month: index % 12 + 1, language: language)
    }
}
