import Supabase
import SwiftUI

struct NotificationPrefs: Codable, Equatable {
    let userID: UUID
    var quietEnabled = false
    var quietFrom = "22:00"
    var quietTo = "07:00"
    var timeZone = TimeZone.current.identifier

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case quietEnabled = "quiet_enabled"
        case quietFrom = "quiet_from"
        case quietTo = "quiet_to"
        case timeZone = "time_zone"
    }

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

/// Notisbehörighet och tysta timmar. Tysta timmar gäller på servern, som väntar med notisen tills de tar slut.
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
                    Toggle("Tysta timmar", isOn: binding(\.quietEnabled))
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
            } else if prefs?.quietEnabled == true {
                Text("Notiser som kommer under tysta timmar skickas samlade när de tar slut.")
            }
        }
        .task { await load() }
    }

    private func load() async {
        await push.refreshAuthorization()
        guard let userID = Backend.client.auth.currentUser?.id else { return }
        do {
            let saved: [NotificationPrefs] = try await Backend.client.from("notification_prefs")
                .select("user_id, quiet_enabled, quiet_from, quiet_to, time_zone")
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

    private func binding(_ field: WritableKeyPath<NotificationPrefs, Bool>) -> Binding<Bool> {
        Binding(get: { prefs?[keyPath: field] ?? false }, set: { value in
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
