import CoreGraphics
import Foundation
import ImageIO

/// The demo Mac's screen for `remote.screenshot`: a desktop in Pebble's sage, a menu bar and two windows, drawn here
/// (no image files), as a JPEG like the bridge sends.
enum DemoScreen {
    static func jpeg(width: Int = 1280, height: Int = 832) -> Data? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let w = CGFloat(width)
        let h = CGFloat(height)
        let desktop = [
            CGColor(srgbRed: 0.55, green: 0.66, blue: 0.58, alpha: 1), CGColor(srgbRed: 0.20, green: 0.29, blue: 0.25, alpha: 1),
        ]
        if let gradient = CGGradient(colorsSpace: space, colors: desktop as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])
        }
        // The menu bar.
        context.setFillColor(CGColor(gray: 0.97, alpha: 0.8))
        context.fill(CGRect(x: 0, y: h - 24, width: w, height: 24))
        // An editor window and Pebble's window beside it.
        window(context, CGRect(x: w * 0.05, y: h * 0.12, width: w * 0.55, height: h * 0.74), lines: 18)
        window(context, CGRect(x: w * 0.64, y: h * 0.20, width: w * 0.31, height: h * 0.60), lines: 9, accent: true)
        // The Dock.
        context.setFillColor(CGColor(gray: 1, alpha: 0.35))
        context.addPath(CGPath(roundedRect: CGRect(x: w * 0.3, y: 8, width: w * 0.4, height: 54), cornerWidth: 16, cornerHeight: 16, transform: nil))
        context.fillPath()
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func window(_ context: CGContext, _ frame: CGRect, lines: Int, accent: Bool = false) {
        context.setFillColor(CGColor(gray: 0, alpha: 0.18))
        context.addPath(CGPath(roundedRect: frame.offsetBy(dx: 0, dy: -6), cornerWidth: 12, cornerHeight: 12, transform: nil))
        context.fillPath()
        context.setFillColor(CGColor(gray: 0.99, alpha: 1))
        context.addPath(CGPath(roundedRect: frame, cornerWidth: 12, cornerHeight: 12, transform: nil))
        context.fillPath()
        // Title bar and its three buttons.
        context.setFillColor(CGColor(gray: 0.93, alpha: 1))
        context.fill(CGRect(x: frame.minX, y: frame.maxY - 30, width: frame.width, height: 18))
        for (index, gray) in [0.85, 0.80, 0.75].enumerated() {
            context.setFillColor(CGColor(gray: gray, alpha: 1))
            context.fillEllipse(in: CGRect(x: frame.minX + 12 + CGFloat(index) * 18, y: frame.maxY - 22, width: 11, height: 11))
        }
        // Lines of text.
        for line in 0..<lines {
            let y = frame.maxY - 56 - CGFloat(line) * 22
            guard y > frame.minY + 16 else { break }
            let length = frame.width * (0.35 + 0.5 * CGFloat((line * 37) % 10) / 10)
            let color = accent && line % 3 == 0
                ? CGColor(srgbRed: 0.42, green: 0.55, blue: 0.47, alpha: 0.9) : CGColor(gray: 0.6, alpha: 0.5)
            context.setFillColor(color)
            context.fill(CGRect(x: frame.minX + 20, y: y, width: length - 40, height: 8))
        }
    }
}
