import SwiftUI
import UIKit

/// Webbappens färger (src/app.css), med mörkt läge. Den gröna accenten ligger i Assets
/// (AccentColor), så att också Apples egna vyer, som kalenderns redigering, blir gröna.
extension Color {
    static let paper = Color(light: 0xF5F3EF, dark: 0x16181B)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1F2226)
    static let surfaceSecondary = Color(light: 0xEFECE6, dark: 0x282C31)
    static let ink = Color(light: 0x211F1C, dark: 0xEDEAE5)
    static let inkMuted = Color(light: 0x7D766E, dark: 0x98928A)
    static let hairline = Color(light: 0xE6E1D8, dark: 0x2F343A)
    /// Samma gröna som AccentColor, men den blir inte grå när en knapp är avstängd.
    static let accent = Color("AccentColor")
    /// Text och ikoner på den gröna accenten.
    static let onAccent = Color(light: 0xF5F3EF, dark: 0x10201B)
    static let checked = Color(light: 0x3E8E5A, dark: 0x6FBF8D)
    static let danger = Color(light: 0xC2503E, dark: 0xE07260)
    static let info = Color(light: 0x2563EB, dark: 0x7FB2FF)
    static let warningBackground = Color(light: 0xF7ECD4, dark: 0x3A3222)
    static let warningText = Color(light: 0x7A5A18, dark: 0xECD9A0)

    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension View {
    /// Webbappens papper bakom listor och formulär, i stället för iOS grå.
    func paperBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.paper)
    }

    /// Vit yta med tunn kant och mjuk skugga, som webbappens kort. `stripe` är en färgad kant till
    /// vänster, i personens färg.
    func card(cornerRadius: CGFloat = 13, stripe: Color? = nil) -> some View {
        background(Color.surface)
            .overlay(alignment: .leading) {
                if let stripe {
                    stripe.frame(width: 4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.hairline)
            }
            .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.05), radius: 7, y: 4)
    }

    /// En rad i en lista som ett eget kort, med luft mellan korten. Svep för att ta bort fungerar
    /// som vanligt.
    func cardRow(stripe: Color? = nil) -> some View {
        padding(.vertical, 12)
            .padding(.horizontal, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(stripe: stripe)
            .plainRow(top: 4.5, bottom: 4.5)
    }

    /// En rad utan kort, direkt på papperet: rubriker, filter och tomma lägen.
    func plainRow(top: CGFloat = 4, bottom: CGFloat = 4) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 18, bottom: bottom, trailing: 18))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// Textfält som webbappens: vit yta och tunn kant som blir grön när man skriver i fältet.
    func paperField(isFocused: Bool) -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isFocused ? Color.accentColor : Color.hairline, lineWidth: 1.5)
            }
            .shadow(color: isFocused ? Color.accentColor.opacity(0.2) : .clear, radius: 3)
    }
}

/// "NYLIGEN I INKÖP" med en kort grön linje före, som webbappens rubriker över listor.
struct SectionTitle<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Color.accentColor.opacity(0.55))
                .frame(width: 16, height: 3)
            Text(title.uppercased())
                .font(.caption.weight(.heavy))
                .tracking(1)
                .foregroundStyle(Color.inkMuted)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// En liten knapp bredvid en rubrik, som "Rensa".
struct SmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.hairline)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Webbappens gröna knapp.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.onAccent)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(colors: [Color.accent.opacity(0.88), Color.accent], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .shadow(color: Color.accent.opacity(isEnabled ? 0.35 : 0), radius: 8, y: 6)
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Webbappens runda bock. Bocken ritas och rutan studsar innan raden flyttas, så att man ser att
/// den bockades av. `label` gör hela raden tryckbar, som på inköpslistan.
struct CheckButton<Label: View>: View {
    let isOn: Bool
    let accessibilityLabel: String
    let action: () -> Void
    let label: Label
    @State private var isChecking = false

    init(isOn: Bool, accessibilityLabel: String, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.isOn = isOn
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: check) {
            HStack(spacing: 12) {
                CheckMark(isOn: isOn || isChecking)
                label
            }
            // Träffytan är större än bocken, utan att raden blir bredare.
            .padding(10)
            .contentShape(Rectangle())
            .padding(-10)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: isChecking) { _, checking in checking }
        .accessibilityLabel(accessibilityLabel)
    }

    private func check() {
        guard !isChecking else { return }
        if isOn {
            action()
            return
        }
        isChecking = true
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            action()
            isChecking = false
        }
    }
}

extension CheckButton where Label == EmptyView {
    init(isOn: Bool, accessibilityLabel: String, action: @escaping () -> Void) {
        self.init(isOn: isOn, accessibilityLabel: accessibilityLabel, action: action) { EmptyView() }
    }
}

private struct CheckMark: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isOn ? Color.checked : Color.clear)
            Circle()
                .strokeBorder(isOn ? Color.checked : Color.hairline, lineWidth: 2)
            Tick()
                .trim(from: 0, to: isOn ? 1 : 0)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                .frame(width: 11, height: 9)
        }
        .frame(width: 23, height: 23)
        .animation(.easeOut(duration: 0.3), value: isOn)
        .keyframeAnimator(initialValue: 1.0, trigger: isOn) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(0.8, duration: 0.08)
                SpringKeyframe(1.2, duration: 0.15)
                SpringKeyframe(1.0, duration: 0.25)
            }
        }
    }
}

private struct Tick: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.width * 0.38, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
    }
}

/// Initialen i personens färg. Gemensamt visas som två personer i grönt.
struct PersonAvatar: View {
    @Environment(AppSession.self) private var session
    let assignee: UUID?
    var size: CGFloat = 28

    var body: some View {
        let person = session.person(assignee)
        Circle()
            .fill(session.color(for: assignee))
            .frame(width: size, height: size)
            .overlay {
                if let person {
                    Text(person.name.prefix(1).uppercased())
                        .font(.system(size: size * 0.43, weight: .bold))
                } else {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: size * 0.34, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .accessibilityElement()
            .accessibilityLabel(person.map { "För \($0.name)" } ?? "Gemensamt")
    }
}

/// "Försenad", "Idag" och "Imorgon" som små etiketter, som i webbappen.
struct DueBadge: View {
    enum Kind {
        case overdue, today, later

        init(daysLeft: Int) {
            self = daysLeft < 0 ? .overdue : daysLeft == 0 ? .today : .later
        }
    }

    let text: String
    let kind: Kind

    var body: some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .fixedSize()
    }

    private var foreground: Color {
        switch kind {
        case .overdue: .danger
        case .today: .info
        case .later: .inkMuted
        }
    }

    private var background: Color {
        switch kind {
        case .overdue: Color.danger.opacity(0.15)
        case .today: Color.info.opacity(0.14)
        case .later: .surfaceSecondary
        }
    }
}

/// Två eller fler lägen i en grå kapsel, där det valda ligger på ett vitt kort, som webbappens
/// "Att göra | Städ".
struct PillTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = option.value == selection
                Button {
                    withAnimation(.snappy) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isSelected ? Color.ink : Color.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.surface)
                                    .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.surfaceSecondary, in: Capsule())
    }
}

/// Tomt läge som ett kort med en emoji, som i webbappen.
struct EmptyCard: View {
    let emoji: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Text(emoji)
                .font(.title2)
                .frame(width: 58, height: 58)
                .background(Color.surfaceSecondary, in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(Color.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .card(cornerRadius: 18)
        .plainRow(top: 4.5, bottom: 4.5)
    }
}
