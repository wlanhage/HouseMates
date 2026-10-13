import SwiftUI

extension Color {
    /// Gemensamt: samma gröna som i webbappen.
    static let shared = Color(hex: "#3F9A63")

    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension AppSession {
    /// Den det gäller, eller nil för gemensamt (också om personen har lämnat hushållet).
    func person(_ id: UUID?) -> Profile? {
        guard let id else { return nil }
        return [me, partner].compactMap { $0 }.first { $0.id == id }
    }

    func color(for assignee: UUID?) -> Color {
        person(assignee).map { Color(hex: $0.color) } ?? .shared
    }

    func name(for assignee: UUID?) -> String {
        person(assignee)?.name ?? "Gemensamt"
    }

    /// Vem något kan vara för: gemensamt, jag eller partnern.
    var assigneeChoices: [AssigneeChoice] {
        [AssigneeChoice(id: nil, name: "Gemensamt")]
            + [me, partner].compactMap { $0 }.map { AssigneeChoice(id: $0.id, name: $0.name) }
    }
}

struct AssigneeChoice: Identifiable {
    let id: UUID?       // nil = gemensamt
    let name: String
}

/// Vems uppgifter och sysslor som visas: allas, en persons eller de gemensamma.
enum AssigneeFilter: Hashable {
    case everyone
    case person(UUID)
    case shared

    /// `assignee` som `AppSession.person` ser den, så att någon som lämnat räknas som gemensamt.
    func includes(_ assignee: UUID?) -> Bool {
        switch self {
        case .everyone: true
        case let .person(id): assignee == id
        case .shared: assignee == nil
        }
    }
}

/// Gemensamt, jag eller partnern.
struct AssigneePicker: View {
    @Environment(AppSession.self) private var session
    @Binding var assignee: UUID?

    var body: some View {
        Picker("För vem", selection: $assignee) {
            ForEach(session.assigneeChoices) { choice in
                Text(choice.name).tag(choice.id)
            }
        }
        .pickerStyle(.segmented)
    }
}

/// Färgad prick och namn: vem något är för.
struct PersonLabel: View {
    @Environment(AppSession.self) private var session
    let assignee: UUID?

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(session.color(for: assignee))
                .frame(width: 8, height: 8)
            Text(session.name(for: assignee))
        }
    }
}
