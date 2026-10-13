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
        person(assignee)?.name ?? String(appLocalized: "Gemensamt")
    }

    /// Vem något kan vara för: gemensamt, jag eller partnern.
    var assigneeChoices: [AssigneeChoice] {
        [AssigneeChoice(id: nil, name: String(appLocalized: "Gemensamt"))]
            + [me, partner].compactMap { $0 }.map { AssigneeChoice(id: $0.id, name: $0.name) }
    }
}

struct AssigneeChoice: Identifiable {
    let id: UUID?       // nil = gemensamt
    let name: String
}

/// Vems uppgifter och sysslor som visas: allas (också de gemensamma) eller en persons.
enum AssigneeFilter: Hashable {
    case everyone
    case person(UUID)

    func includes(_ assignee: UUID?) -> Bool {
        switch self {
        case .everyone: true
        case let .person(id): assignee == id
        }
    }
}

/// Gemensamt, jag eller partnern. Det valda fylls med personens färg, som i webbappen.
struct AssigneePicker: View {
    @Environment(AppSession.self) private var session
    @Binding var assignee: UUID?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(session.assigneeChoices) { choice in
                let isSelected = choice.id == assignee
                Button {
                    assignee = choice.id
                } label: {
                    Text(choice.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? Color.white : Color.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(isSelected ? session.color(for: choice.id) : Color.surfaceSecondary, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("För vem")
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
