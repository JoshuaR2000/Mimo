import RealityKit
import simd
#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformColor = UIColor
#endif

extension PlatformColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// Darkens a hex color toward black by `amount` (0...1).
func darken(_ hex: UInt32, _ amount: Float) -> UInt32 {
    let k = 1 - amount
    let r = UInt32(Float((hex >> 16) & 0xFF) * k), g = UInt32(Float((hex >> 8) & 0xFF) * k), b = UInt32(Float(hex & 0xFF) * k)
    return (r << 16) | (g << 8) | b
}

enum Mat {
    static func pbr(_ hex: UInt32, roughness: Float, metallic: Float = 0, clearcoat: Float = 0) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: PlatformColor(hex: hex))
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: metallic)
        m.clearcoat = .init(floatLiteral: clearcoat)
        m.clearcoatRoughness = .init(floatLiteral: 0.2)
        return m
    }

    static func glow(_ hex: UInt32, opacity: Float = 1) -> UnlitMaterial {
        var m = UnlitMaterial(color: PlatformColor(hex: hex))
        if opacity < 1 { m.blending = .transparent(opacity: .init(floatLiteral: opacity)) }
        return m
    }
}

func euler(_ x: Float, _ y: Float, _ z: Float) -> simd_quatf {
    simd_quatf(angle: x, axis: [1, 0, 0]) * simd_quatf(angle: y, axis: [0, 1, 0]) * simd_quatf(angle: z, axis: [0, 0, 1])
}
