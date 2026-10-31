import Foundation

/// One sRGB colour as Pebble writes it in `src/tokens.css` ("#506e54", "#7d8df266"), plus the WCAG 2 contrast maths
/// that Pebble's `src/tokens.test.mjs` uses. Pure data: the SwiftUI colours are built from these values
/// (`PebbleColor`), and the tests measure them.
nonisolated public struct PebbleRGB: Hashable, Sendable, CustomStringConvertible {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    /// 0...1. Only Pebble's glow tokens are translucent.
    public let alpha: Double

    /// `hex` is 0xRRGGBB.
    public init(_ hex: UInt32, alpha: Double = 1) {
        red = UInt8((hex >> 16) & 0xFF)
        green = UInt8((hex >> 8) & 0xFF)
        blue = UInt8(hex & 0xFF)
        self.alpha = min(max(alpha, 0), 1)
    }

    /// Parses a CSS hex colour: `#rgb`, `#rrggbb` or `#rrggbbaa`. Anything else is nil.
    public init?(css: String) {
        let trimmed = css.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        var digits = String(trimmed.dropFirst())
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        if digits.count == 8 {
            self.init(UInt32(value >> 8), alpha: Double(value & 0xFF) / 255)
        } else {
            self.init(UInt32(value))
        }
    }

    /// "#rrggbb", or "#rrggbbaa" when translucent: the form tokens.css uses.
    public var description: String {
        let rgb = String(format: "#%02x%02x%02x", red, green, blue)
        guard alpha < 1 else { return rgb }
        return rgb + String(format: "%02x", Int((alpha * 255).rounded()))
    }

    public var isOpaque: Bool { alpha >= 1 }

    /// WCAG 2 relative luminance of the opaque colour (alpha ignored, as tokens.test.mjs does).
    public var relativeLuminance: Double {
        func channel(_ value: UInt8) -> Double {
            let c = Double(value) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG 2 contrast ratio, 1...21.
    public func contrast(with other: PebbleRGB) -> Double {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// This colour laid over an opaque `background` (for translucent tokens).
    public func over(_ background: PebbleRGB) -> PebbleRGB {
        func mix(_ top: UInt8, _ bottom: UInt8) -> UInt32 {
            UInt32((Double(top) * alpha + Double(bottom) * (1 - alpha)).rounded())
        }
        return PebbleRGB(mix(red, background.red) << 16 | mix(green, background.green) << 8 | mix(blue, background.blue))
    }

    /// Components in 0...1 for colour APIs.
    public var components: (red: Double, green: Double, blue: Double, alpha: Double) {
        (Double(red) / 255, Double(green) / 255, Double(blue) / 255, alpha)
    }
}
