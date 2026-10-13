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
}
