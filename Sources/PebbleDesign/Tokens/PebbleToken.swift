/// Every colour token in Pebble's `src/tokens.css`, with its light (`:root`) and dark (`:root[data-theme="dark"]`)
/// value. The raw value is the CSS name without `--`. Aliases (`surface`, `border`, `danger-bg`, `avatar-body`,
/// `focus`) are resolved here the way CSS resolves `var()`, so each theme has exactly one value per token.
/// `PebbleParityTests` compares this table with tokens.css whenever the Pebble checkout is on this Mac.
nonisolated public enum PebbleToken: String, CaseIterable, Sendable {
    // Surfaces
    case bg, side, panel, surface, soft, code, hover, selected, selection
    case userBubble = "user-bubble"
    case dangerBackground = "danger-bg"
    // Text
    case text, secondary, muted, danger
    /// Pebble's success and caution inks (tokens.css `--ok`, `--warn`).
    case ok, warn
    // Lines and controls
    case line, border
    case lineStrong = "line-strong"
    case dangerLine = "danger-line"
    case disabled
    case controlOff = "control-off"
    // The accent
    case accent, focus
    case accentSoft = "accent-soft"
    case onAccent = "on-accent"
    // The avatar
    case avatar
    case avatarEye = "avatar-eye"
    case avatarBody = "avatar-body"
    // The Veil, Stealth Lockdown's dusk family (Phase 33, D57)
    case avatarStealth = "avatar-stealth"
    case avatarStealthHi = "avatar-stealth-hi"
    case avatarStealthEye = "avatar-stealth-eye"
    case avatarStealthRim = "avatar-stealth-rim"
    case avatarStealthGlow = "avatar-stealth-glow"
    case stealthGlow = "stealth-glow"
    case stealthGlowSoft = "stealth-glow-soft"
    case stealthInk = "stealth-ink"
    case stealthSoft = "stealth-soft"
    case stealthLine = "stealth-line"
    // Charts' series, in order (1.9.29's VisualChart.vue); the first is the accent
    case chart1 = "chart-1", chart2 = "chart-2", chart3 = "chart-3", chart4 = "chart-4", chart5 = "chart-5"
    case chart6 = "chart-6"

    /// The six series colours in Pebble's order: series i takes the (i mod 6)th.
    public static let chartSeries: [PebbleToken] = [.chart1, .chart2, .chart3, .chart4, .chart5, .chart6]

    /// The name in tokens.css, without the leading `--`.
    public var cssName: String { rawValue }

    public var light: PebbleRGB {
        switch self {
        case .bg, .dangerBackground: PebbleRGB(0xf8f9f6)
        case .side: PebbleRGB(0xf1f3ee)
        case .panel, .surface: PebbleRGB(0xffffff)
        case .text: PebbleRGB(0x252c28)
        case .secondary: PebbleRGB(0x5d665e)
        case .muted: PebbleRGB(0x636b63)
        case .line, .border: PebbleRGB(0xe5e9e1)
        case .lineStrong: PebbleRGB(0xdbe1d6)
        case .accent, .focus, .avatarBody, .chart1: PebbleRGB(0x506e54)
        case .accentSoft: PebbleRGB(0xb0c2ae)
        case .onAccent: PebbleRGB(0xffffff)
        case .soft: PebbleRGB(0xf0f5ed)
        case .selected: PebbleRGB(0xe5ebe0)
        case .hover: PebbleRGB(0xe9eee5)
        case .disabled: PebbleRGB(0xc7cec3)
        case .controlOff: PebbleRGB(0x7d877e)
        case .code: PebbleRGB(0xf3f5f0)
        case .userBubble: PebbleRGB(0xeaf0e5)
        case .avatar: PebbleRGB(0x536b54)
        case .avatarEye: PebbleRGB(0xffffff)
        case .avatarStealth: PebbleRGB(0x44528c)
        case .avatarStealthHi: PebbleRGB(0x7684c6)
        case .avatarStealthEye: PebbleRGB(0xffffff)
        case .avatarStealthRim: PebbleRGB(0xd6ddff)
        case .avatarStealthGlow, .stealthGlow: PebbleRGB(0x7d8df2)
        case .stealthGlowSoft: PebbleRGB(0x7d8df2, alpha: Double(0x66) / 255)
        case .stealthInk: PebbleRGB(0x3b4785)
        case .stealthSoft: PebbleRGB(0xeef0fb)
        case .stealthLine: PebbleRGB(0xcdd3f1)
        case .selection: PebbleRGB(0xd4e5c8)
        case .danger: PebbleRGB(0xa45141)
        case .ok: PebbleRGB(0x3f6f45)
        case .warn: PebbleRGB(0x8a5a00)
        case .dangerLine: PebbleRGB(0xebd3ca)
        case .chart2: PebbleRGB(0xa5622a)
        case .chart3: PebbleRGB(0x5a61a6)
        case .chart4: PebbleRGB(0xa5465d)
        case .chart5: PebbleRGB(0x2c7584)
        case .chart6: PebbleRGB(0x6f742a)
        }
    }

    public var dark: PebbleRGB {
        switch self {
        case .bg, .dangerBackground: PebbleRGB(0x191e1b)
        case .side: PebbleRGB(0x151a17)
        case .panel, .surface: PebbleRGB(0x212822)
        case .text: PebbleRGB(0xe0e7de)
        case .secondary: PebbleRGB(0xadb9ab)
        case .muted: PebbleRGB(0x94a192)
        case .line, .border: PebbleRGB(0x2b342c)
        case .lineStrong: PebbleRGB(0x39443a)
        case .accent, .focus, .avatarBody, .chart1: PebbleRGB(0xa6c795)
        case .accentSoft: PebbleRGB(0x52684b)
        case .onAccent: PebbleRGB(0x1b281a)
        case .soft: PebbleRGB(0x273425)
        case .selected: PebbleRGB(0x293628)
        case .hover: PebbleRGB(0x263026)
        case .disabled: PebbleRGB(0x445142)
        case .controlOff: PebbleRGB(0x6f7c6d)
        case .code: PebbleRGB(0x161d17)
        case .userBubble: PebbleRGB(0x2c3928)
        case .avatar: PebbleRGB(0xb4cda6)
        case .avatarEye: PebbleRGB(0x23351f)
        case .avatarStealth: PebbleRGB(0xa3aeea)
        case .avatarStealthHi: PebbleRGB(0xccd4fb)
        case .avatarStealthEye: PebbleRGB(0x1c2246)
        case .avatarStealthRim: PebbleRGB(0xffffff)
        case .avatarStealthGlow, .stealthGlow: PebbleRGB(0x8494f7)
        case .stealthGlowSoft: PebbleRGB(0x8494f7, alpha: Double(0x77) / 255)
        case .stealthInk: PebbleRGB(0xb8c2f6)
        case .stealthSoft: PebbleRGB(0x262b42)
        case .stealthLine: PebbleRGB(0x3c4470)
        case .selection: PebbleRGB(0x425d35)
        case .danger: PebbleRGB(0xe3a38f)
        case .ok: PebbleRGB(0x8fcf8f)
        case .warn: PebbleRGB(0xe0b25c)
        case .dangerLine: PebbleRGB(0x66483d)
        case .chart2: PebbleRGB(0xe3a46c)
        case .chart3: PebbleRGB(0xa7adf0)
        case .chart4: PebbleRGB(0xe89bae)
        case .chart5: PebbleRGB(0x7cc4d1)
        case .chart6: PebbleRGB(0xc9cd7c)
        }
    }

    public func value(dark isDark: Bool) -> PebbleRGB { isDark ? dark : light }

    /// The token Increase Contrast shows instead, if any. Both are Pebble's own tokens, so the contrast tests cover
    /// them: muted text reads as secondary text, and hairlines use the strong line.
    public var increasedContrast: PebbleToken? {
        switch self {
        case .muted: .secondary
        case .line, .border: .lineStrong
        default: nil
        }
    }
}
