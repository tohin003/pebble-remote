import Foundation
import Testing

@testable import PebbleDesign

/// Pebble's contrast rule (src/tokens.test.mjs, ported): every text token reaches WCAG AA (4.5:1) on every surface
/// token in both themes, text on the accent fill too, and the off switch's track is a visible control (3:1). The phone
/// adds iOS's own backgrounds (system, grouped, elevated), the Veil's text, and the avatar's parts as graphics (3:1).
struct ContrastTests {
    static let text: [PebbleToken] = [.text, .secondary, .muted, .danger]
    static let surfaces: [PebbleToken] = [.bg, .side, .panel, .surface, .soft, .code, .userBubble, .hover, .selected]

    /// iOS's system backgrounds (sRGB), light and dark, base and elevated (a sheet's grouped cells are #2c2c2e).
    /// Not #3a3a3c, the tertiary elevated fill: muted text measures 4.2:1 there, so text on it uses `secondaryText`
    /// (docs/DESIGN.md, "Colour").
    static let iosLight = ["#ffffff", "#f2f2f7"].compactMap(PebbleRGB.init(css:))
    static let iosDark = ["#000000", "#1c1c1e", "#2c2c2e"].compactMap(PebbleRGB.init(css:))

    @Test func onTheTertiaryElevatedFillSecondaryTextReads() throws {
        let fill = try #require(PebbleRGB(css: "#3a3a3c"))
        for token in [PebbleToken.text, .secondary, .danger, .accent] {
            #expect(token.dark.contrast(with: fill) >= 4.5, "--\(token.cssName) on #3a3a3c")
        }
    }

    @Test func theFormulaMatchesWCAGsReferenceValues() throws {
        let black = try #require(PebbleRGB(css: "#000000")), white = try #require(PebbleRGB(css: "#fff"))
        #expect(String(format: "%.2f", black.contrast(with: white)) == "21.00")
        #expect(String(format: "%.2f", PebbleRGB(0x767676).contrast(with: white)) == "4.54")
        #expect(PebbleRGB(0x939b93).contrast(with: white) < 3)  // Pebble 0.6.1's light --muted, which failed
        #expect(PebbleRGB(0x646d65).contrast(with: PebbleRGB(0xf0f5ed)) >= 4.5)
    }

    @Test(arguments: [false, true])
    func everyTextTokenOnEverySurfaceIsAtLeast4_5(dark: Bool) {
        var failing: [String] = []
        var checked = 0
        for text in Self.text + [.accent] {
            for surface in Self.surfaces {
                checked += 1
                let ratio = text.value(dark: dark).contrast(with: surface.value(dark: dark))
                if ratio < 4.5 { failing.append("--\(text.cssName) on --\(surface.cssName): \(ratio)") }
            }
        }
        #expect(checked == (Self.text.count + 1) * Self.surfaces.count, "the whole grid")
        #expect(failing.isEmpty, "\(dark ? "dark" : "light"): \(failing)")
        #expect(PebbleToken.onAccent.value(dark: dark).contrast(with: PebbleToken.accent.value(dark: dark)) >= 4.5)
    }

    @Test(arguments: [false, true])
    func theOffSwitchIsAVisibleControl(dark: Bool) {
        let track = PebbleToken.controlOff.value(dark: dark)
        for surface in [PebbleToken.panel, .bg, .side] {
            #expect(track.contrast(with: surface.value(dark: dark)) >= 3, "--control-off on --\(surface.cssName)")
        }
        #expect(PebbleToken.panel.value(dark: dark).contrast(with: track) >= 3, "thumb on the off track")
    }

    /// Pebble's chart rule (1.9.29, tokens.test.mjs): series are graphics, 3:1 on every surface (here also on iOS's own
    /// backgrounds), six distinct colours, and the first is the accent.
    @Test(arguments: [false, true])
    func chartSeriesAreVisibleGraphics(dark: Bool) {
        let series = PebbleToken.chartSeries.map { $0.value(dark: dark) }
        #expect(Set(series).count == 6, "six distinct colours")
        #expect(series.first == PebbleToken.accent.value(dark: dark), "the first series is the accent")
        let backgrounds = Self.surfaces.map { ("--\($0.cssName)", $0.value(dark: dark)) }
            + (dark ? Self.iosDark : Self.iosLight).map { ("\($0)", $0) }
        var failing: [String] = []
        for (index, colour) in series.enumerated() {
            for (name, background) in backgrounds where colour.contrast(with: background) < 3 {
                failing.append("--chart-\(index + 1) on \(name)")
            }
        }
        #expect(failing.isEmpty, "\(dark ? "dark" : "light"): \(failing)")
    }

    @Test(arguments: [false, true])
    func textTokensReadOnIOSBackgrounds(dark: Bool) {
        var failing: [String] = []
        for surface in dark ? Self.iosDark : Self.iosLight {
            for text in Self.text + [.accent] {
                let ratio = text.value(dark: dark).contrast(with: surface)
                if ratio < 4.5 { failing.append("--\(text.cssName) on \(surface): \(ratio)") }
            }
        }
        #expect(failing.isEmpty, "\(failing)")
    }

    @Test(arguments: [false, true])
    func increaseContrastStandInsAreAtLeastAsStrong(dark: Bool) {
        for token in PebbleToken.allCases {
            guard let strong = token.increasedContrast else { continue }
            let background = PebbleToken.panel.value(dark: dark)
            #expect(
                strong.value(dark: dark).contrast(with: background) >= token.value(dark: dark).contrast(with: background),
                "\(token.cssName) -> \(strong.cssName)")
        }
    }

    @Test(arguments: [false, true])
    func theVeilsTextReads(dark: Bool) {
        let ink = PebbleToken.stealthInk.value(dark: dark)
        for surface in [PebbleToken.stealthSoft, .panel, .bg] {
            #expect(ink.contrast(with: surface.value(dark: dark)) >= 4.5, "--stealth-ink on --\(surface.cssName)")
        }
        // the Stealth row's other text sits on the Veil's soft background
        for text in [PebbleToken.text, .secondary] {
            #expect(
                text.value(dark: dark).contrast(with: PebbleToken.stealthSoft.value(dark: dark)) >= 4.5,
                "--\(text.cssName) on --stealth-soft")
        }
    }

    @Test(arguments: [false, true])
    func theAvatarsPartsAreVisibleGraphics(dark: Bool) {
        let body = PebbleToken.avatar.value(dark: dark)
        #expect(PebbleToken.avatarEye.value(dark: dark).contrast(with: body) >= 3, "eyes on the body")
        let veil = PebbleToken.avatarStealth.value(dark: dark)
        #expect(PebbleToken.avatarStealthEye.value(dark: dark).contrast(with: veil) >= 3, "Veil eyes on the Veil")
        for surface in Self.surfaces.map({ $0.value(dark: dark) }) + (dark ? Self.iosDark : Self.iosLight) {
            #expect(body.contrast(with: surface) >= 3, "the pebble on \(surface)")
        }
    }

    @Test func tokensParseAndPrintAsCSS() throws {
        #expect(PebbleRGB(css: "#abc")?.description == "#aabbcc")
        #expect(PebbleRGB(css: "#7d8df266")?.description == "#7d8df266")
        #expect(PebbleRGB(css: "7d8df2") == nil)
        #expect(PebbleRGB(css: "#12345") == nil)
        #expect(PebbleToken.stealthGlowSoft.light.isOpaque == false)
        let mixed = PebbleToken.stealthGlowSoft.light.over(PebbleRGB(0xffffff))
        #expect(mixed.isOpaque)
    }
}
