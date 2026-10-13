import Supabase
import SwiftUI

struct NotificationPrefs: Codable, Equatable {
    let userID: UUID
    var quietEnabled = false
    var quietFrom = "22:00"
    var quietTo = "07:00"
    var timeZone = TimeZone.current.identifier
    var digestMinutes = 3

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case quietEnabled = "quiet_enabled"
        case quietFrom = "quiet_from"
        case quietTo = "quiet_to"
        case timeZone = "time_zone"
        case digestMinutes = "digest_minutes"
    }

    /// Valen för "Skicka när det varit tyst i"; servern tar 0–120 minuter.
    static let digestChoices = [0, 1, 3, 5, 10, 15, 30, 60, 120]

    /// Tysta timmar gäller i telefonens tidszon; efter en resa flyttas de med.
    static func syncTimeZone() async {
        guard let userID = Backend.client.auth.currentUser?.id else { return }
        let zone = TimeZone.current.identifier
        _ = try? await Backend.client.from("notification_prefs")
            .update(["time_zone": zone])
            .eq("user_id", value: userID)
            .neq("time_zone", value: zone)
            .execute()
    }
}

/// Notisbehörighet, hur länge det ska vara tyst innan notisen går och tysta timmar. Båda gäller på
/// servern, som väntar med notisen.
struct NotificationSection: View {
    @Environment(\.openURL) private var openURL
    @State private var prefs: NotificationPrefs?
    @State private var errorMessage: String?
    @State private var saving: Task<Void, Never>?
    private let push = Push.shared

    var body: some View {
        Section {
            switch push.authorization {
            case .authorized, .provisional, .ephemeral:
                if let prefs {
                    Picker("Skicka när det varit tyst i", selection: binding(\.digestMinutes, empty: 3)) {
                        ForEach(NotificationPrefs.digestChoices, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    Toggle("Tysta timmar", isOn: binding(\.quietEnabled, empty: false))
                    if prefs.quietEnabled {
                        DatePicker("Från", selection: timeBinding(\.quietFrom), displayedComponents: .hourAndMinute)
                        DatePicker("Till", selection: timeBinding(\.quietTo), displayedComponents: .hourAndMinute)
                    }
                } else {
                    LabeledContent("Notiser", value: "På")
                }
            case .denied:
                Button("Slå på notiser i Inställningar") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            default:
                Button("Slå på notiser") { Task { await push.requestPermission() } }
            }
        } header: {
            Text("Notiser")
        } footer: {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            } else if let prefs, notificationsAreOn {
                Text(prefs.quietEnabled
                    ? "Ändringar i rad blir en samlad notis. Notiser under tysta timmar skickas när de tar slut."
                    : "Ändringar i rad blir en samlad notis.")
            }
        }
        .task { await load() }
    }

    private var notificationsAreOn: Bool {
        [.authorized, .provisional, .ephemeral].contains(push.authorization)
    }

    private func load() async {
        await push.refreshAuthorization()
        guard let userID = Backend.client.auth.currentUser?.id else { return }
        do {
            let saved: [NotificationPrefs] = try await Backend.client.from("notification_prefs")
                .select("user_id, quiet_enabled, quiet_from, quiet_to, time_zone, digest_minutes")
                .eq("user_id", value: userID)
                .execute()
                .value
            prefs = saved.first ?? NotificationPrefs(userID: userID)
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    private func save(_ updated: NotificationPrefs) {
        var updated = updated
        updated.timeZone = TimeZone.current.identifier
        prefs = updated
        // I tur och ordning, så att den senaste ändringen alltid är den som gäller på servern.
        saving = Task { [previous = saving] in
            await previous?.value
            do {
                try await Backend.client.from("notification_prefs").upsert(updated).execute()
                errorMessage = nil
            } catch {
                errorMessage = userMessage(for: error)
            }
        }
    }

    private func binding<Value>(_ field: WritableKeyPath<NotificationPrefs, Value>, empty: Value) -> Binding<Value> {
        Binding(get: { prefs?[keyPath: field] ?? empty }, set: { value in
            guard var updated = prefs else { return }
            updated[keyPath: field] = value
            save(updated)
        })
    }

    private func timeBinding(_ field: WritableKeyPath<NotificationPrefs, String>) -> Binding<Date> {
        Binding(get: { ClockTime.date(from: prefs?[keyPath: field] ?? "00:00") }, set: { date in
            guard var updated = prefs else { return }
            updated[keyPath: field] = ClockTime.string(from: date)
            save(updated)
        })
    }
}

/// Klockslag som "HH:MM", så som servern sparar dem.
enum ClockTime {
    static func date(from text: String, on day: Date = .now) -> Date {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return day }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day) ?? day
    }

    static func string(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}
