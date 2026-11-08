// Draws Mimo's app icon (Zuri's face) as a 1024×1024 PNG.
// Usage: swift tools/make-icon.swift <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func gradient(_ colors: [CGColor], _ locs: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locs)! }

// Background: deep space, top to bottom
ctx.drawLinearGradient(gradient([rgb(0x2B2F7A), rgb(0x120F33)], [0, 1]), start: CGPoint(x: 512, y: 1024), end: CGPoint(x: 512, y: 0), options: [])
// A few stars
for (x, y, r) in [(140, 860, 6.0), (880, 900, 5.0), (930, 760, 4.0), (110, 640, 4.0), (930, 380, 5.0), (110, 300, 4.0)] as [(Int, Int, CGFloat)] {
    ctx.setFillColor(rgb(0xFFFFFF, 0.8)); ctx.fillEllipse(in: CGRect(x: CGFloat(x) - r, y: CGFloat(y) - r, width: r * 2, height: r * 2))
}
// Glow ring at the bottom
ctx.setStrokeColor(rgb(0x6FF3FF, 0.9)); ctx.setLineWidth(14)
ctx.strokeEllipse(in: CGRect(x: 232, y: 70, width: 560, height: 120))

// Head: big bulb plus a narrower chin, shaded with a radial gradient
let head = CGMutablePath()
head.addEllipse(in: CGRect(x: 192, y: 330, width: 640, height: 600))
head.addEllipse(in: CGRect(x: 342, y: 220, width: 340, height: 330))
ctx.saveGState()
ctx.addPath(head); ctx.clip()
ctx.drawRadialGradient(gradient([rgb(0xD4EA6A), rgb(0xA9C23F), rgb(0x6E8424)], [0, 0.55, 1]),
                       startCenter: CGPoint(x: 420, y: 760), startRadius: 10, endCenter: CGPoint(x: 512, y: 600), endRadius: 470, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.restoreGState()

// Eyes: huge glossy black almonds, slanted up at the outer corners
for side: CGFloat in [-1, 1] {
    ctx.saveGState()
    ctx.translateBy(x: 512 + side * 140, y: 600)
    ctx.rotate(by: side * 0.38)
    let eye = CGRect(x: -125, y: -78, width: 250, height: 156)
    ctx.addEllipse(in: eye); ctx.clip()
    ctx.drawRadialGradient(gradient([rgb(0x3A3D4A), rgb(0x050608)], [0, 1]),
                           startCenter: CGPoint(x: -30, y: 30), startRadius: 5, endCenter: .zero, endRadius: 140, options: [])
    ctx.resetClip()
    ctx.setFillColor(rgb(0xFFFFFF, 0.95)); ctx.fillEllipse(in: CGRect(x: -62, y: 18, width: 38, height: 38))
    ctx.setFillColor(rgb(0xFFFFFF, 0.8)); ctx.fillEllipse(in: CGRect(x: 48, y: -36, width: 14, height: 14))
    ctx.restoreGState()
}
// Small smile
ctx.setStrokeColor(rgb(0x2A1626)); ctx.setLineWidth(14); ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 462, y: 365)); ctx.addQuadCurve(to: CGPoint(x: 562, y: 365), control: CGPoint(x: 512, y: 325)); ctx.strokePath()
// Blush
for side: CGFloat in [-1, 1] {
    ctx.setFillColor(rgb(0xFF8FA8, 0.8)); ctx.fillEllipse(in: CGRect(x: 512 + side * 170 - 45, y: 420, width: 90, height: 44))
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("wrote \(url.path)")
