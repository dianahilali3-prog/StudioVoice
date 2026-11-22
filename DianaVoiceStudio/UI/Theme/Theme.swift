import SwiftUI
import UIKit

/// DianaVoiceStudio palette: powder pink, black and metallic silver,
/// adapted to light and dark mode.
enum Theme {
    // MARK: Colors

    /// Powder pink — main accent.
    static let rose = Color(light: 0xE59AAE, dark: 0xF2B4C4)
    /// Deeper pink for text/icons on light backgrounds (contrast).
    static let roseDeep = Color(light: 0xB8436A, dark: 0xF5A3B9)
    /// Very light pink wash.
    static let roseMist = Color(light: 0xFBE7EC, dark: 0x2A1A20)
    /// Main background.
    static let background = Color(light: 0xFBF6F7, dark: 0x09090B)
    /// Card surface.
    static let surface = Color(light: 0xFFFFFF, dark: 0x151518)
    /// Raised surface (fields inside cards).
    static let surfaceRaised = Color(light: 0xF6F1F3, dark: 0x1E1E22)
    /// Primary text ("ink").
    static let ink = Color(light: 0x0B0B0D, dark: 0xF6F2F3)
    /// Metallic silver for secondary elements.
    static let silver = Color(light: 0x8A8C94, dark: 0xB9BBC3)
    static let silverLight = Color(light: 0xD5D6DB, dark: 0x3A3B41)
    /// Pure black (buttons, accents).
    static let black = Color(light: 0x0B0B0D, dark: 0x0B0B0D)

    // MARK: Gradients

    static let roseGradient = LinearGradient(
        colors: [Color(hex: 0xF6C6D3), Color(hex: 0xE89AB0), Color(hex: 0xD97D98)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let silverGradient = LinearGradient(
        colors: [Color(hex: 0xF4F4F6), Color(hex: 0xB4B6BE), Color(hex: 0xE9EAEE), Color(hex: 0x8D8F98)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let silverGradientSoft = LinearGradient(
        colors: [Color(hex: 0xF4F4F6, opacity: 0.6), Color(hex: 0xB4B6BE, opacity: 0.6), Color(hex: 0xE9EAEE, opacity: 0.6), Color(hex: 0x8D8F98, opacity: 0.6)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let blackGradient = LinearGradient(
        colors: [Color(hex: 0x1D1D21), Color(hex: 0x050506)],
        startPoint: .top, endPoint: .bottom)

    // MARK: Metrics

    static let cornerRadius: CGFloat = 22
    static let buttonHeight: CGFloat = 58
    static let maxContentWidth: CGFloat = 720
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// Dynamic color resolved for light / dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Card

struct CardModifier: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.surface)
                    .shadow(color: Color.black.opacity(0.06), radius: 14, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.silverGradientSoft, lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// Centers content with a comfortable reading width on large screens.
    func readableWidth() -> some View {
        frame(maxWidth: Theme.maxContentWidth)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Section header

struct SectionLabel: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.roseDeep)
            }
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(Theme.silver)
        }
    }
}
