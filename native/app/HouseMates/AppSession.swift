import Foundation
import Observation
import Supabase

/// Vem som är inloggad och vilket hushåll hen tillhör. Styr vilken skärm RootView visar.
@MainActor
@Observable
final class AppSession {
    enum Phase { case loading, signedOut, needsHousehold, ready }

    private(set) var phase: Phase = .loading
    private(set) var me: Profile?
    private(set) var partner: Profile?
    private(set) var household: Household?
    private(set) var loadError: String?

    private let client = Backend.client

    func start() async {
        for await (_, session) in client.auth.authStateChanges {
            await load(signedIn: session != nil)
        }
    }

    func reload() async {
        await load(signedIn: client.auth.currentSession != nil)
    }

    /// Svarar true när e-postadressen måste bekräftas innan inloggning (standard i ett hostat projekt).
    func signUp(name: String, email: String, password: String) async throws -> Bool {
        let response = try await client.auth.signUp(email: email, password: password, data: ["name": .string(name)])
        if case .user = response { return true }
        return false
    }

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }

    func signOut() async {
        await Push.shared.unregisterDevice()
        try? await client.auth.signOut()
    }

    /// Raderar kontot och allt kopplat till det på servern (delete_account), sedan det appen sparat på telefonen.
    func deleteAccount() async throws {
        try await client.rpc("delete_account").execute()
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        try? await client.auth.signOut()
    }

    func leaveHousehold() async throws {
        try await client.rpc("leave_household").execute()
        await reload()
    }

    func createHousehold() async throws {
        try await client.rpc("create_household").execute()
        await reload()
    }

    func joinHousehold(code: String) async throws {
        try await client.rpc("join_household", params: ["p_code": code]).execute()
        await reload()
    }

    func saveCalendarLink(title: String, eventUIDs: [String]) async throws {
        try await client.rpc("set_calendar_link", params: SetCalendarLink(p_title: title, p_uids: eventUIDs)).execute()
        await reload()
    }

    /// Kalendern finns bara i telefonerna; servern får veta vad som hänt så att partnern kan få en notis.
    func logCalendarActivity(_ activity: CalendarActivity) async {
        let params = CalendarActivityParams(
            p_type: activity.type, p_event_uid: activity.eventUID, p_title: activity.title, p_start: activity.start
        )
        _ = try? await client.rpc("log_calendar_activity", params: params).execute()
    }

    private func load(signedIn: Bool) async {
        guard signedIn, let userID = client.auth.currentUser?.id else {
            me = nil
            partner = nil
            household = nil
            phase = .signedOut
            return
        }
        do {
            // RLS ger bara den egna profilen och partnerns, och bara det egna hushållet.
            let profiles: [Profile] = try await client.from("profiles").select("id, name").execute().value
            guard profiles.contains(where: { $0.id == userID }) else {
                // Profilen skapas tillsammans med kontot, så den saknas bara om kontot har raderats.
                await signOut()
                return
            }
            let households: [Household] = try await client.from("households").select().execute().value
            me = profiles.first { $0.id == userID }
            partner = profiles.first { $0.id != userID }
            household = households.first
            loadError = nil
            phase = household == nil ? .needsHousehold : .ready
            await Push.shared.uploadToken()
        } catch {
            loadError = userMessage(for: error)
        }
    }
}

private struct SetCalendarLink: Encodable {
    let p_title: String
    let p_uids: [String]
}

private struct CalendarActivityParams: Encodable {
    let p_type: String
    let p_event_uid: String
    let p_title: String
    let p_start: String
}
