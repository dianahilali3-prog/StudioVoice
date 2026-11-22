import SwiftUI

/// Large pink gradient button — main actions (« Générer », « Télécharger »).
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(Theme.black)
            .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.roseGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
            )
            .shadow(color: Theme.rose.opacity(configuration.isPressed ? 0.15 : 0.4), radius: configuration.isPressed ? 4 : 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Black button with silver outline — secondary actions (« Écouter », « Choisir une voix »).
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(colorScheme == .dark ? Theme.ink : Color.white)
            .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(colorScheme == .dark ? AnyShapeStyle(Theme.surfaceRaised) : AnyShapeStyle(Theme.blackGradient))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.silverGradient, lineWidth: 1.2)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Discrete silver pill (toolbar actions inside cards).
struct PillButtonStyle: ButtonStyle {
    var tint: Color = Theme.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .background(Capsule().fill(Theme.surfaceRaised))
            .overlay(Capsule().strokeBorder(Theme.silverLight, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Round icon button (player controls).
struct CircleIconButtonStyle: ButtonStyle {
    var size: CGFloat = 54
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(prominent ? Theme.black : Theme.ink)
            .frame(width: size, height: size)
            .background(
                Circle().fill(prominent ? AnyShapeStyle(Theme.roseGradient) : AnyShapeStyle(Theme.surfaceRaised))
            )
            .overlay(Circle().strokeBorder(prominent ? Theme.silverGradientSoft : Theme.silverGradient, lineWidth: 1))
            .shadow(color: prominent ? Theme.rose.opacity(0.45) : .clear, radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var dvPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var dvSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var dvPill: PillButtonStyle { PillButtonStyle() }
}
