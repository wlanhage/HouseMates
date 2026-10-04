import Foundation

/// What the partner's phone needs to find the same calendar: its title and the UIDs of a few events in it.
/// Travels as a link, so it can be sent in Messages and then tapped or pasted.
struct LinkCode {
    let calendarTitle: String
    let eventUIDs: [String]

    init(calendarTitle: String, eventUIDs: [String]) {
        self.calendarTitle = calendarTitle
        self.eventUIDs = eventUIDs
    }

    init?(url: URL) {
        guard url.scheme == "kalendertest", url.host() == "koppla",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }
        let uids = items.filter { $0.name == "uid" }.compactMap(\.value)
        guard !uids.isEmpty else { return nil }
        calendarTitle = items.first { $0.name == "titel" }?.value ?? ""
        eventUIDs = uids
    }

    /// Finds the link in pasted text such as "Koppla HouseMates till vår kalender kalendertest://koppla?…".
    init?(text: String) {
        guard let range = text.range(of: #"kalendertest://\S+"#, options: .regularExpression),
              let url = URL(string: String(text[range])) else {
            return nil
        }
        self.init(url: url)
    }

    /// One piece of text with the link inside: copying from the share sheet keeps only the text, never a separate URL.
    var shareText: String {
        "Koppla HouseMates till vår kalender: \(url.absoluteString)"
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = "kalendertest"
        components.host = "koppla"
        components.queryItems = [URLQueryItem(name: "titel", value: calendarTitle)]
            + eventUIDs.map { URLQueryItem(name: "uid", value: $0) }
        return components.url!
    }
}
