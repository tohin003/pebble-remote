import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Pebble's palette as SwiftUI colours that follow the system's light and dark appearance and Increase Contrast.
/// Values come from `PebbleToken` (Pebble's tokens.css). Where to use which: docs/DESIGN.md, "Colour".
///
/// - Text in the content layer uses `text`, `secondaryText` and `mutedText`: each reaches 4.5:1 on every Pebble
///   surface and on iOS's system backgrounds, in both appearances (`ContrastTests`).
/// - Text on Liquid Glass uses the system's `.primary` and `.secondary` styles instead, which glass makes vibrant.
/// - `accent` is the app's tint (also `App/Assets.xcassets/AccentColor`). Text on an accent fill is `onAccent`.
nonisolated public enum PebbleColor {
    // Surfaces
    public static let bg = Color(.bg)
    public static let side = Color(.side)
    public static let panel = Color(.panel)
    public static let soft = Color(.soft)
    public static let code = Color(.code)
    public static let hover = Color(.hover)
    public static let selected = Color(.selected)
    public static let selection = Color(.selection)
    public static let userBubble = Color(.userBubble)
    // Text
    public static let text = Color(.text)
    public static let secondaryText = Color(.secondary)
    public static let mutedText = Color(.muted)
    public static let danger = Color(.danger)
    public static let ok = Color(.ok)
    public static let warn = Color(.warn)
    // Lines and controls
    public static let line = Color(.line)
    public static let lineStrong = Color(.lineStrong)
    public static let dangerLine = Color(.dangerLine)
    public static let disabled = Color(.disabled)
    public static let controlOff = Color(.controlOff)
    // The accent: Pebble's sage
    public static let accent = Color(.accent)
    public static let accentSoft = Color(.accentSoft)
    public static let onAccent = Color(.onAccent)
    // The avatar
    public static let avatar = Color(.avatar)
    public static let avatarEye = Color(.avatarEye)
    // The Veil (Stealth Lockdown)
    public static let avatarStealth = Color(.avatarStealth)
    public static let avatarStealthHi = Color(.avatarStealthHi)
    public static let avatarStealthEye = Color(.avatarStealthEye)
    public static let avatarStealthRim = Color(.avatarStealthRim)
    public static let avatarStealthGlow = Color(.avatarStealthGlow)
    public static let stealthGlow = Color(.stealthGlow)
    public static let stealthGlowSoft = Color(.stealthGlowSoft)
    public static let stealthInk = Color(.stealthInk)
    public static let stealthSoft = Color(.stealthSoft)
    public static let stealthLine = Color(.stealthLine)
    // Charts: the series colours in Pebble's order (graphics: 3:1 on every surface, `ContrastTests`)
    public static let chartSeries: [Color] = PebbleToken.chartSeries.map { Color($0) }

    /// A token's colour for an explicit appearance (previews, the avatar's renderer, icons).
    public static func fixed(_ token: PebbleToken, dark: Bool) -> Color {
        Color(rgb: token.value(dark: dark))
    }
}

nonisolated extension Color {
    /// A dynamic colour for one of Pebble's tokens: light or dark with the system, and the token's Increase Contrast
    /// stand-in when that setting is on.
    public init(_ token: PebbleToken) {
        let light = token.light, dark = token.dark
        let strongLight = token.increasedContrast?.light ?? light
        let strongDark = token.increasedContrast?.dark ?? dark
        #if canImport(UIKit)
        self.init(
            uiColor: UIColor { traits in
                let isDark = traits.userInterfaceStyle == .dark
                let strong = traits.accessibilityContrast == .high
                return (isDark ? (strong ? strongDark : dark) : (strong ? strongLight : light)).platformColor
            })
        #elseif canImport(AppKit)
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [
                    .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
                ])
                switch match {
                case .some(.darkAqua): return dark.platformColor
                case .some(.accessibilityHighContrastDarkAqua): return strongDark.platformColor
                case .some(.accessibilityHighContrastAqua): return strongLight.platformColor
                default: return light.platformColor
                }
            })
        #else
        self.init(rgb: light)
        #endif
    }

    /// A fixed sRGB colour from a token value.
    public init(rgb: PebbleRGB) {
        let c = rgb.components
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }
}

#if canImport(UIKit)
nonisolated extension PebbleRGB {
    var platformColor: UIColor {
        let c = components
        return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }
}
#elseif canImport(AppKit)
nonisolated extension PebbleRGB {
    var platformColor: NSColor {
        let c = components
        return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }
}
#endif
