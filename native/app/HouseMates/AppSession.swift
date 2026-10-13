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
    /// Visar "Nytt lösenord" efter en återställningslänk.
    var needsNewPassword = false
    /// Inställningar öppnas som ett ark från kugghjulet på flikarna (`SettingsButton`).
    var showsSettings = false
    var linkError: String?

    private let client = Backend.client

    /// Dit länkarna i mejlen leder; adresserna måste också finnas i Supabase (additional_redirect_urls).
    static let signedInLink = URL(string: "housemates://inloggad")!
    static let newPasswordLink = URL(string: "housemates://nytt-losenord")!

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
        let response = try await client.auth.signUp(
            email: email, password: password, data: ["name": .string(name)], redirectTo: Self.signedInLink
        )
        if case .user = response { return true }
        return false
    }

    /// Länkar från mejlen: bekräftat konto loggar in, återställningslänken frågar efter nytt lösenord.
    /// Andra länkar till appen öppnar den bara.
    func handle(_ url: URL) async {
        let mailLinks = [Self.signedInLink, Self.newPasswordLink]
        guard mailLinks.contains(where: { $0.scheme == url.scheme && $0.host() == url.host() }) else { return }
        do {
            try await client.auth.session(from: url)
            needsNewPassword = url.host() == Self.newPasswordLink.host()
        } catch is URLError {
            linkError = String(appLocalized: "Ingen kontakt med servern. Öppna länken igen när du har nät.")
        } catch {
            // Servern säger sällan varför; det vanliga är en gammal länk eller en annan telefon.
            linkError = String(appLocalized: "Länken har gått ut, redan använts eller öppnats på en annan telefon än den som bad om den. Be om en ny.")
        }
    }

    /// Länken fungerar bara på den här telefonen: den bär en engångskod som appen sparat lokalt (PKCE).
    func requestPasswordReset(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email, redirectTo: Self.newPasswordLink)
    }

    func setNewPassword(_ password: String) async throws {
        try await client.auth.update(user: UserAttributes(password: password))
        needsNewPassword = false
    }

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }

    func signOut() async {
        await Push.shared.unregisterDevice()
        LocalFiles.removeAll()
        try? await client.auth.signOut()
        // SDK:n meddelar inte alltid utloggningen (t.ex. om inloggningen redan hade gått ut).
        await load(signedIn: false)
    }

    /// Raderar kontot och allt kopplat till det på servern (delete_account), sedan det appen sparat på telefonen.
    func deleteAccount() async throws {
        try await client.rpc("delete_account").execute()
        LocalFiles.removeAll()
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        // Språkvalet försvinner med resten, också delningstilläggets kopia.
        UserDefaults(suiteName: RecipeInbox.appGroup)?.removeObject(forKey: AppLanguage.storageKey)
        try? await client.auth.signOut()
        await load(signedIn: false)
    }

    func leaveHousehold() async throws {
        try await client.rpc("leave_household").execute()
        LocalFiles.removeAll()
        await reload()
    }

    func createHousehold() async throws {
        try await client.rpc("create_household").execute()
        await reload()
    }

    func joinHousehold(code: String) async throws {
        let joined: Bool = try await client.rpc("join_household", params: ["p_code": code]).execute().value
        guard joined else { throw UserFacingError(message: String(appLocalized: "Hittade inget hushåll med den koden.")) }
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
        // Senast kända läge visas direkt, så att appen går att använda även utan nät (t.ex. i butiken).
        if phase == .loading, let saved = LocalFiles.read(SavedSession.self, from: Self.sessionFile), saved.me.id == userID {
            show(saved)
        }
        do {
            // Inloggningen kontrolleras först: utan den skulle svaren nedan vara tomma, och en tom
            // profil får inte tolkas som ett raderat konto.
            _ = try await client.auth.session
            // RLS ger bara den egna profilen och partnerns, och bara det egna hushållet.
            let profiles: [Profile] = try await client.from("profiles").select("id, name, color").execute().value
            let households: [Household] = try await client.from("households").select().execute().value
            // Hann användaren logga ut medan svaren var på väg gäller de inte längre.
            guard client.auth.currentUser?.id == userID else { return }
            guard let me = profiles.first(where: { $0.id == userID }) else {
                // Profilen skapas tillsammans med kontot, så den saknas bara om kontot har raderats.
                await signOut()
                return
            }
            let session = SavedSession(me: me, partner: profiles.first { $0.id != userID }, household: households.first)
            show(session)
            LocalFiles.write(session, to: Self.sessionFile)
            loadError = nil
            await Push.shared.uploadToken()
        } catch {
            loadError = userMessage(for: error)
        }
    }

    private func show(_ session: SavedSession) {
        me = session.me
        partner = session.partner
        household = session.household
        phase = household == nil ? .needsHousehold : .ready
    }

    private static let sessionFile = "session.json"
}

private struct SavedSession: Codable {
    let me: Profile
    let partner: Profile?
    let household: Household?
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
