import SwiftUI

/// Webbappens toppbar: era två prickar och namnet till vänster, kugghjulet till höger. Den ligger
/// kvar överst och listan rullar in under den.
struct AppTopBar: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        HStack {
            HStack(spacing: 9) {
                PairDots()
                Text(verbatim: "HouseMates")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Color.ink)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            SettingsButton()
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.bottom, 2)
        .background(Color.paper.opacity(0.85))
        .background(.ultraThinMaterial)
    }
}

/// Två överlappande prickar i era färger. Utan partner är den andra pricken grå.
private struct PairDots: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        HStack(spacing: -7) {
            dot(session.color(for: session.me?.id))
            dot(session.partner.map { Color(hex: $0.color) } ?? Color.hairline)
        }
        .accessibilityHidden(true)
    }

    private func dot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 16, height: 16)
            .overlay { Circle().strokeBorder(Color.paper, lineWidth: 2.5) }
    }
}

/// Sidans rubrik under toppbaren, som webbappens "Inköp", med plats för en knapp till höger.
struct PageTitle<Trailing: View>: View {
    let title: LocalizedStringKey
    let trailing: Trailing

    init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.title.weight(.heavy))
                .foregroundStyle(Color.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
        }
        .plainRow(top: 2, bottom: 6)
    }
}

extension PageTitle where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.init(title) { EmptyView() }
    }
}

/// Rund ikonknapp i toppbaren och bredvid rubriker, som webbappens.
struct IconButtonLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(Color.inkMuted)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }
}
