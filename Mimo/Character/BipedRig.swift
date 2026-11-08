import RealityKit
import simd

/// Facial values that blend smoothly between moods.
struct Face {
    var browY: Float = 0, browTilt: Float = 0, browAsym: Float = 0
    var eyeOpen: Float = 1, eyeHappy: Float = 0
    var mouthCurve: Float = 0.3, mouthOpen: Float = 0, mouthRound: Float = 0
    var tilt: Float = 0, pitch: Float = 0, blush: Float = 0

    mutating func approach(_ o: Face, _ k: Float) {
        browY += (o.browY - browY) * k; browTilt += (o.browTilt - browTilt) * k; browAsym += (o.browAsym - browAsym) * k
        eyeOpen += (o.eyeOpen - eyeOpen) * k; eyeHappy += (o.eyeHappy - eyeHappy) * k
        mouthCurve += (o.mouthCurve - mouthCurve) * k; mouthOpen += (o.mouthOpen - mouthOpen) * k; mouthRound += (o.mouthRound - mouthRound) * k
        tilt += (o.tilt - tilt) * k; pitch += (o.pitch - pitch) * k; blush += (o.blush - blush) * k
    }

    static func target(_ mood: Mood) -> Face {
        var f = Face()
        switch mood {
        case .neutral: break
        case .happy: f.browY = 0.012; f.eyeHappy = 0.8; f.mouthCurve = 1; f.mouthOpen = 0.25; f.tilt = 0.06; f.blush = 0.7; f.pitch = -0.05
        case .laughing: f.browY = 0.016; f.eyeHappy = 1; f.mouthCurve = 1; f.mouthOpen = 0.9; f.tilt = -0.05; f.blush = 0.9; f.pitch = -0.18
        case .sad: f.browY = 0.004; f.browTilt = -0.3; f.eyeOpen = 0.62; f.mouthCurve = -0.9; f.tilt = -0.1; f.pitch = 0.22
        case .surprised: f.browY = 0.026; f.eyeOpen = 1.25; f.mouthCurve = 0; f.mouthOpen = 0.8; f.mouthRound = 1; f.pitch = -0.08
        case .thinking: f.browY = 0.006; f.browTilt = 0.1; f.browAsym = 0.014; f.eyeOpen = 0.82; f.mouthCurve = -0.2; f.tilt = 0.13; f.pitch = -0.12
        case .concerned: f.browY = -0.006; f.browTilt = 0.3; f.eyeOpen = 0.78; f.mouthCurve = -0.6; f.pitch = 0.08
        }
        return f
    }
}

/// Joint angles for one arm.
struct ArmPose {
    var z: Float, x: Float, ex: Float, ez: Float
    mutating func approach(_ o: ArmPose, _ k: Float) {
        z += (o.z - z) * k; x += (o.x - x) * k; ex += (o.ex - ex) * k; ez += (o.ez - ez) * k
    }
    static let rest = ArmPose(z: 0.12, x: 0, ex: -0.1, ez: 0)
    static let chin = ArmPose(z: -0.4, x: -1.0, ex: -2.0, ez: 0)
    static func target(_ mood: Mood) -> ArmPose {
        switch mood {
        case .neutral, .thinking: .rest
        case .happy: ArmPose(z: 0.35, x: 0, ex: -0.3, ez: 0)
        case .laughing: ArmPose(z: 0.1, x: -0.6, ex: -1.3, ez: 0)
        case .sad: ArmPose(z: 0.04, x: 0.08, ex: 0, ez: 0)
        case .surprised: ArmPose(z: 0.7, x: -0.2, ex: -0.9, ez: 0)
        case .concerned: ArmPose(z: -0.15, x: -0.65, ex: -1.15, ez: 0)
        }
    }
}

/// What a part's material follows when the palette changes.
private enum Role { case primary, primaryShade, secondary, tertiary, fixed }

/// A two-legged character (alien, robot or human) built from smooth shapes and animated every frame.
@MainActor
final class BipedRig {
    let kind: CharacterKind
    let root = Entity()

    // Skeleton
    private let torso = Entity(), neck = Entity(), head = Entity()
    private var shoulders: [Entity] = [], elbows: [Entity] = [], hips: [Entity] = []
    private var armPoses: [ArmPose] = [.rest, .rest]

    // Face parts
    private struct Eye { let ball: ModelEntity; let lid: ModelEntity?; let glint: ModelEntity?; let baseScale: SIMD3<Float>; let basePos: SIMD3<Float>; let lidMax: Float }
    private var eyes: [Eye] = []
    private var brows: [(entity: ModelEntity, side: Float, base: SIMD3<Float>, baseRot: simd_quatf)] = []
    private var mouthSides: [(entity: ModelEntity, side: Float)] = []
    private var mouthCenter: ModelEntity?
    private var mouthHole: ModelEntity?
    private var mouthBase: SIMD3<Float> = .zero
    private var mouthSpacing: Float = 0.042
    private var mouthHoleSize: SIMD3<Float> = [0.032, 0.034, 0.012]
    private var cheeks: [ModelEntity] = []
    private var ring: ModelEntity?

    // Material bookkeeping
    private var parts: [(entity: ModelEntity, role: Role)] = []
    private var appliedPalette: String?

    // Animation state
    private var face = Face()
    private var time: Float = 0
    private var blink: Float = 0, blinkIn: Float = 1.5, blinkT: Float = -1
    private var gesture: CharacterGesture?, gestureT: Float = 0, seenToken = -1
    private var shownBlush: Float = -1

    init(kind: CharacterKind, palette: Palette) {
        self.kind = kind
        build()
        applyPalette(palette)
    }

    // MARK: - Building helpers

    @discardableResult
    private func part(_ parent: Entity, _ size: SIMD3<Float>, at pos: SIMD3<Float> = .zero, rot: simd_quatf = euler(0, 0, 0),
                      mesh: MeshResource? = nil, role: Role = .primary, material: (any Material)? = nil) -> ModelEntity {
        let e = ModelEntity(mesh: mesh ?? .generateSphere(radius: 1), materials: [material ?? SimpleMaterial()])
        e.scale = size
        e.position = pos
        e.orientation = rot
        parent.addChild(e)
        if material == nil || role != .fixed { parts.append((e, role)) }
        return e
    }

    private func box(_ parent: Entity, _ size: SIMD3<Float>, corner: Float, at pos: SIMD3<Float> = .zero, role: Role = .primary, material: (any Material)? = nil) -> ModelEntity {
        let minSide = min(size.x, size.y, size.z)
        let mesh = MeshResource.generateBox(size: size, cornerRadius: min(corner, minSide / 2))
        let e = ModelEntity(mesh: mesh, materials: [material ?? SimpleMaterial()])
        e.position = pos
        parent.addChild(e)
        if material == nil || role != .fixed { parts.append((e, role)) }
        return e
    }

    private func cylinder(_ parent: Entity, height: Float, radius: Float, at pos: SIMD3<Float> = .zero, rot: simd_quatf = euler(0, 0, 0), role: Role = .secondary, material: (any Material)? = nil) -> ModelEntity {
        let e = ModelEntity(mesh: .generateCylinder(height: height, radius: radius), materials: [material ?? SimpleMaterial()])
        e.position = pos
        e.orientation = rot
        parent.addChild(e)
        if material == nil || role != .fixed { parts.append((e, role)) }
        return e
    }

    private func material(for role: Role, _ p: Palette) -> (any Material)? {
        switch (kind, role) {
        case (_, .fixed): return nil
        case (.alien, .primary): return Mat.pbr(p.primary, roughness: 0.38, clearcoat: 0.35)
        case (.alien, _): return Mat.pbr(darken(p.primary, 0.22), roughness: 0.4, clearcoat: 0.3)
        case (.robot, .primary): return Mat.pbr(p.primary, roughness: 0.28, metallic: 0.15, clearcoat: 0.8)
        case (.robot, .primaryShade): return Mat.pbr(darken(p.primary, 0.2), roughness: 0.3, metallic: 0.2, clearcoat: 0.6)
        case (.robot, .secondary): return Mat.pbr(p.secondary, roughness: 0.35, metallic: 0.85)
        case (.robot, .tertiary): return Mat.glow(p.tertiary)
        case (.human, .primary): return Mat.pbr(p.primary, roughness: 0.55, clearcoat: 0.1)
        case (.human, .primaryShade): return Mat.pbr(darken(p.primary, 0.12), roughness: 0.55)
        case (.human, .secondary): return Mat.pbr(p.secondary, roughness: 0.85)
        case (.human, .tertiary): return Mat.pbr(p.tertiary, roughness: 0.7, clearcoat: 0.2)
        }
    }

    private func applyPalette(_ p: Palette) {
        appliedPalette = p.id
        var cache: [String: any Material] = [:]
        for item in parts {
            let key = "\(item.role)"
            if cache[key] == nil, let m = material(for: item.role, p) { cache[key] = m }
            if let m = cache[key] { item.entity.model?.materials = [m] }
        }
        if kind == .robot {
            // Robot face glow follows the palette's glow color.
            let glow = Mat.glow(p.tertiary)
            for e in eyes { e.ball.model?.materials = [glow] }
            for b in brows { b.entity.model?.materials = [glow] }
            for m in mouthSides { m.entity.model?.materials = [glow] }
            mouthCenter?.model?.materials = [glow]
            mouthHole?.model?.materials = [glow]
        }
    }

    // MARK: - Body

    private var shoulderX: Float { kind == .alien ? 0.15 : (kind == .robot ? 0.24 : 0.2) }

    private func build() {
        buildLegs()
        torso.position = [0, 0.95, 0]; root.addChild(torso)
        buildTorso()
        buildArms()
        neck.position = [0, 0.6, 0]; torso.addChild(neck)
        head.position = [0, 0.15, 0]; neck.addChild(head)
        switch kind {
        case .alien: buildAlienHead()
        case .robot: buildRobotHead()
        case .human: buildHumanHead()
        }
        buildPad()
    }

    private func buildLegs() {
        let pants = Mat.pbr(0x2E3550, roughness: 0.8)
        let shoe = Mat.pbr(0x23262E, roughness: 0.5, clearcoat: 0.4)
        for side: Float in [-1, 1] {
            let hip = Entity(); hip.position = [side * (kind == .alien ? 0.085 : 0.1), 0.95, 0]; root.addChild(hip); hips.append(hip)
            let knee = Entity(); knee.position = [0, -0.46, 0]; hip.addChild(knee)
            let ankle = Entity(); ankle.position = [0, -0.47, 0]; knee.addChild(ankle)
            switch kind {
            case .alien:
                part(hip, [0.058, 0.26, 0.062], at: [0, -0.22, 0])
                part(knee, [0.048, 0.25, 0.052], at: [0, -0.22, 0])
                part(ankle, [0.05, 0.03, 0.05])
                for spread in [Float(-0.5), 0, 0.5] {
                    let toe = Entity(); toe.orientation = euler(0, spread, 0); ankle.addChild(toe)
                    part(toe, [0.022, 0.018, 0.1], at: [0, -0.005, 0.085])
                    part(toe, [0.03, 0.02, 0.03], at: [0, -0.005, 0.175])
                }
            case .robot:
                _ = cylinder(hip, height: 0.4, radius: 0.04, at: [0, -0.22, 0])
                part(knee, [0.065, 0.065, 0.065], role: .secondary)
                _ = box(knee, [0.13, 0.38, 0.14], corner: 0.05, at: [0, -0.22, 0])
                _ = box(ankle, [0.16, 0.08, 0.26], corner: 0.035, at: [0, 0.0, 0.04], role: .primaryShade)
            case .human:
                part(hip, [0.075, 0.26, 0.08], at: [0, -0.22, 0], role: .fixed, material: pants)
                part(knee, [0.062, 0.25, 0.068], at: [0, -0.22, 0], role: .fixed, material: pants)
                part(ankle, [0.07, 0.05, 0.13], at: [0, 0.01, 0.04], role: .fixed, material: shoe)
                part(ankle, [0.072, 0.012, 0.135], at: [0, -0.03, 0.04], role: .fixed, material: Mat.pbr(0xF2F2F2, roughness: 0.6))
            }
        }
    }

    private func buildTorso() {
        switch kind {
        case .alien:
            part(torso, [0.115, 0.13, 0.085], at: [0, 0.08, 0])
            part(torso, [0.105, 0.22, 0.08], at: [0, 0.28, 0])
            part(torso, [0.135, 0.17, 0.088], at: [0, 0.45, 0])
        case .robot:
            _ = box(torso, [0.26, 0.16, 0.2], corner: 0.05, at: [0, 0.08, 0], role: .secondary)
            _ = box(torso, [0.42, 0.46, 0.26], corner: 0.1, at: [0, 0.38, 0])
            _ = cylinder(torso, height: 0.02, radius: 0.05, at: [0, 0.42, 0.13], rot: euler(.pi / 2, 0, 0), role: .tertiary)
            for i in 0..<3 {
                _ = box(torso, [0.16, 0.015, 0.01], corner: 0.005, at: [0, 0.27 - Float(i) * 0.035, 0.131], role: .secondary)
            }
        case .human:
            part(torso, [0.14, 0.11, 0.1], at: [0, 0.07, 0], role: .fixed, material: Mat.pbr(0x2E3550, roughness: 0.8))
            part(torso, [0.165, 0.27, 0.11], at: [0, 0.36, 0], role: .secondary)
            part(torso, [0.11, 0.04, 0.08], at: [0, 0.58, 0.0], role: .secondary)
        }
    }

    private func buildArms() {
        for side: Float in [-1, 1] {
            let shoulder = Entity(); shoulder.position = [side * shoulderX, 0.56, 0]; torso.addChild(shoulder); shoulders.append(shoulder)
            let elbow = Entity(); elbow.position = [0, -0.38, 0]; shoulder.addChild(elbow); elbows.append(elbow)
            let wrist = Entity(); wrist.position = [0, -0.37, 0]; elbow.addChild(wrist)
            switch kind {
            case .alien:
                part(shoulder, [0.042, 0.042, 0.042])
                part(shoulder, [0.04, 0.21, 0.043], at: [0, -0.19, 0])
                part(elbow, [0.036, 0.2, 0.038], at: [0, -0.18, 0])
                part(wrist, [0.04, 0.05, 0.022], at: [0, -0.035, 0])
                for (i, dx) in [Float(-0.024), 0, 0.024].enumerated() {
                    let finger = Entity(); finger.position = [dx, -0.07, 0]; finger.orientation = euler(0, 0, (Float(i) - 1) * 0.18); wrist.addChild(finger)
                    part(finger, [0.014, 0.075, 0.015], at: [0, -0.07, 0])
                    part(finger, [0.019, 0.019, 0.019], at: [0, -0.145, 0])
                }
                let thumb = Entity(); thumb.position = [-side * 0.035, -0.04, 0.012]; thumb.orientation = euler(0, 0, -side * 0.7); wrist.addChild(thumb)
                part(thumb, [0.01, 0.045, 0.012], at: [0, -0.04, 0])
            case .robot:
                part(shoulder, [0.075, 0.075, 0.075], role: .secondary)
                _ = cylinder(shoulder, height: 0.32, radius: 0.035, at: [0, -0.19, 0])
                part(elbow, [0.055, 0.055, 0.055], role: .secondary)
                _ = box(elbow, [0.1, 0.3, 0.1], corner: 0.04, at: [0, -0.18, 0])
                _ = box(wrist, [0.1, 0.1, 0.06], corner: 0.03, at: [0, -0.05, 0], role: .primaryShade)
                for dx in [Float(-0.03), 0.03] {
                    _ = box(wrist, [0.025, 0.07, 0.03], corner: 0.012, at: [dx, -0.12, 0], role: .secondary)
                }
            case .human:
                part(shoulder, [0.06, 0.06, 0.06], role: .secondary)
                part(shoulder, [0.05, 0.2, 0.052], at: [0, -0.18, 0], role: .secondary)
                part(elbow, [0.038, 0.19, 0.04], at: [0, -0.18, 0])
                part(wrist, [0.045, 0.055, 0.026], at: [0, -0.04, 0])
                for (i, dx) in [Float(-0.027), -0.009, 0.009, 0.027].enumerated() {
                    let finger = Entity(); finger.position = [dx, -0.085, 0]; finger.orientation = euler(0, 0, (Float(i) - 1.5) * 0.06); wrist.addChild(finger)
                    part(finger, [0.01, 0.038, 0.011], at: [0, -0.03, 0])
                }
                let thumb = Entity(); thumb.position = [-side * 0.04, -0.04, 0.012]; thumb.orientation = euler(0, 0, -side * 0.6); wrist.addChild(thumb)
                part(thumb, [0.012, 0.035, 0.013], at: [0, -0.03, 0])
            }
        }
    }

    private func buildPad() {
        let dark = Mat.pbr(0x1B2140, roughness: 0.45, metallic: 0.3)
        let pad = ModelEntity(mesh: .generateCylinder(height: 0.04, radius: 0.75), materials: [dark])
        pad.position = [0, -0.04, 0]
        root.addChild(pad)
        let glow = ModelEntity(mesh: .generateCylinder(height: 0.006, radius: 0.7), materials: [Mat.glow(kind.accent)])
        glow.position = [0, -0.017, 0]
        root.addChild(glow)
        ring = glow
        let inner = ModelEntity(mesh: .generateCylinder(height: 0.008, radius: 0.67), materials: [dark])
        inner.position = [0, -0.014, 0]
        root.addChild(inner)
    }

    // MARK: - Heads

    private func addMouth(at base: SIMD3<Float>, spacing: Float, thickness: Float, hole: SIMD3<Float>, material: any Material, role: Role = .fixed) {
        mouthBase = base
        mouthSpacing = spacing
        mouthHoleSize = hole
        mouthCenter = part(head, [spacing * 0.68, thickness, thickness * 1.6], at: base, role: role, material: material)
        for side: Float in [-1, 1] {
            let e = part(head, [spacing * 0.58, thickness, thickness * 1.6], at: base + [side * spacing, 0, -0.004], role: role, material: material)
            mouthSides.append((e, side))
        }
        mouthHole = part(head, [hole.x, 0.001, hole.z], at: base, role: role, material: material)
    }

    private func addCheeks(at pos: SIMD3<Float>, size: SIMD3<Float>) {
        for side: Float in [-1, 1] {
            let cheek = ModelEntity(mesh: .generateSphere(radius: 1), materials: [Mat.glow(0xFF7A95, opacity: 0.01)])
            cheek.scale = size
            cheek.position = [side * pos.x, pos.y, pos.z]
            cheek.orientation = euler(0, side * 0.6, 0)
            head.addChild(cheek)
            cheeks.append(cheek)
        }
    }

    private func buildAlienHead() {
        head.scale = [1.12, 1.12, 1.12]
        part(neck, [0.035, 0.12, 0.035], at: [0, 0.07, 0])
        part(head, [0.38, 0.36, 0.34], at: [0, 0.42, 0])
        part(head, [0.21, 0.22, 0.2], at: [0, 0.2, 0.05])
        part(head, [0.12, 0.08, 0.1], at: [0, 0.06, 0.08])
        let eyeBlack = Mat.pbr(0x08090C, roughness: 0.06, clearcoat: 1)
        let shine = Mat.pbr(0xFFFFFF, roughness: 0.2)
        for side: Float in [-1, 1] {
            let pivot = Entity()
            pivot.position = [side * 0.165, 0.35, 0.258]
            pivot.orientation = euler(-0.1, side * 0.45, side * 0.38)
            head.addChild(pivot)
            let scale: SIMD3<Float> = [0.155, 0.1, 0.064]
            let ball = part(pivot, scale, role: .fixed, material: eyeBlack)
            part(pivot, [0.02, 0.02, 0.01], at: [-0.055, 0.04, 0.054], role: .fixed, material: shine)
            let glint = part(pivot, [0.008, 0.008, 0.005], at: [0.06, -0.03, 0.056], role: .fixed, material: shine)
            eyes.append(Eye(ball: ball, lid: nil, glint: glint, baseScale: scale, basePos: .zero, lidMax: 0.205))
            let browBase: SIMD3<Float> = [side * 0.165, 0.49, 0.292]
            let browRot = euler(-0.35, 0, 0)
            let brow = part(head, [0.08, 0.009, 0.014], at: browBase, rot: browRot, role: .primaryShade)
            brows.append((brow, side, browBase, browRot))
        }
        let dark = Mat.pbr(0x2A1626, roughness: 0.6)
        for side: Float in [-1, 1] { part(head, [0.008, 0.006, 0.006], at: [side * 0.018, 0.215, 0.252], role: .fixed, material: dark) }
        addMouth(at: [0, 0.13, 0.248], spacing: 0.042, thickness: 0.005, hole: [0.032, 0.034, 0.012], material: dark)
        addCheeks(at: [0.15, 0.2, 0.228], size: [0.05, 0.025, 0.01])
    }

    private func buildRobotHead() {
        let neckCyl = cylinder(neck, height: 0.16, radius: 0.045, at: [0, 0.08, 0])
        _ = neckCyl
        _ = box(head, [0.52, 0.44, 0.42], corner: 0.13, at: [0, 0.28, 0])
        _ = box(head, [0.42, 0.3, 0.02], corner: 0.07, at: [0, 0.28, 0.205], role: .fixed, material: Mat.pbr(0x0A1018, roughness: 0.12, clearcoat: 1))
        for side: Float in [-1, 1] {
            _ = cylinder(head, height: 0.05, radius: 0.08, at: [side * 0.27, 0.28, 0], rot: euler(0, 0, .pi / 2))
            let scale: SIMD3<Float> = [0.048, 0.06, 0.008]
            let eyePos: SIMD3<Float> = [side * 0.095, 0.31, 0.218]
            let ball = part(head, scale, at: eyePos, role: .fixed, material: Mat.glow(0x5EF2FF))
            eyes.append(Eye(ball: ball, lid: nil, glint: nil, baseScale: scale, basePos: eyePos, lidMax: 0))
            let browBase: SIMD3<Float> = [side * 0.095, 0.385, 0.218]
            let brow = part(head, [0.05, 0.008, 0.004], at: browBase, role: .fixed, material: Mat.glow(0x5EF2FF))
            brows.append((brow, side, browBase, euler(0, 0, 0)))
        }
        _ = cylinder(head, height: 0.14, radius: 0.012, at: [0, 0.56, 0])
        part(head, [0.035, 0.035, 0.035], at: [0, 0.645, 0], role: .tertiary)
        addMouth(at: [0, 0.2, 0.218], spacing: 0.04, thickness: 0.007, hole: [0.045, 0.03, 0.004], material: Mat.glow(0x5EF2FF))
    }

    private func buildHumanHead() {
        head.scale = [1.3, 1.3, 1.3]
        part(neck, [0.045, 0.09, 0.045], at: [0, 0.05, 0])
        part(head, [0.2, 0.235, 0.21], at: [0, 0.26, 0])
        part(head, [0.15, 0.12, 0.15], at: [0, 0.13, 0.03])
        for side: Float in [-1, 1] { part(head, [0.03, 0.05, 0.025], at: [side * 0.2, 0.25, -0.01], role: .primaryShade) }
        // Hair
        part(head, [0.215, 0.2, 0.225], at: [0, 0.34, -0.025], role: .tertiary)
        part(head, [0.2, 0.17, 0.16], at: [0, 0.27, -0.08], role: .tertiary)
        part(head, [0.17, 0.055, 0.09], at: [0.03, 0.43, 0.13], rot: euler(-0.35, 0, -0.15), role: .tertiary)
        for side: Float in [-1, 1] {
            part(head, [0.075, 0.2, 0.13], at: [side * 0.175, 0.2, -0.04], rot: euler(0, 0, side * 0.08), role: .tertiary)
        }
        part(head, [0.2, 0.22, 0.11], at: [0, 0.17, -0.11], role: .tertiary)
        // Eyes with iris and pupil inside a unit-sphere sclera so a squint squashes all of it
        let white = Mat.pbr(0xFFFFFF, roughness: 0.15, clearcoat: 1)
        let iris = Mat.pbr(0x5A3A22, roughness: 0.2, clearcoat: 1)
        let pupil = Mat.pbr(0x050505, roughness: 0.1)
        let shine = Mat.pbr(0xFFFFFF, roughness: 0.2)
        for side: Float in [-1, 1] {
            let pivot = Entity()
            pivot.position = [side * 0.078, 0.27, 0.186]
            pivot.orientation = euler(0, side * 0.28, 0)
            head.addChild(pivot)
            let scale: SIMD3<Float> = [0.054, 0.056, 0.034]
            let ball = part(pivot, scale, role: .fixed, material: white)
            part(ball, [0.58, 0.58, 0.25], at: [0, 0, 0.9], role: .fixed, material: iris)
            part(ball, [0.3, 0.3, 0.2], at: [0, 0, 0.98], role: .fixed, material: pupil)
            let glint = part(ball, [0.14, 0.14, 0.1], at: [-0.22, 0.25, 1.0], role: .fixed, material: shine)
            eyes.append(Eye(ball: ball, lid: nil, glint: glint, baseScale: scale, basePos: .zero, lidMax: 0.095))
            let browBase: SIMD3<Float> = [side * 0.08, 0.335, 0.195]
            let browRot = euler(-0.2, side * 0.25, 0)
            let brow = part(head, [0.045, 0.009, 0.012], at: browBase, rot: browRot, role: .tertiary)
            brows.append((brow, side, browBase, browRot))
        }
        part(head, [0.022, 0.032, 0.026], at: [0, 0.21, 0.205], role: .primaryShade)
        addMouth(at: [0, 0.145, 0.19], spacing: 0.03, thickness: 0.006, hole: [0.03, 0.03, 0.012], material: Mat.pbr(0x7A2E35, roughness: 0.5))
        addCheeks(at: [0.11, 0.19, 0.17], size: [0.035, 0.02, 0.01])
    }

    // MARK: - Animation

    func update(dt rawDt: Float, controller c: CharacterController) {
        let dt = min(rawDt, 0.05)
        time += dt
        let t = time
        if c.palette.id != appliedPalette { applyPalette(c.palette) }

        face.approach(.target(c.mood), 1 - exp(-dt * 8))

        blinkIn -= dt
        if blinkIn <= 0 && blinkT < 0 { blinkT = 0; blinkIn = 2 + Float.random(in: 0...3.5) }
        if blinkT >= 0 {
            blinkT += dt
            let p = blinkT / 0.15
            blink = p < 1 ? sin(.pi * p) : 0
            if p >= 1 { blinkT = -1 }
        }

        // Gestures
        if c.gestureToken != seenToken {
            if seenToken >= 0 || c.gesture != nil { gesture = c.gesture; gestureT = 0 }
            seenToken = c.gestureToken
        }
        var nod: Float = 0, shake: Float = 0, jumpY: Float = 0, squash: Float = 0, gTilt: Float = 0
        var overrides: [ArmPose?] = [nil, nil]
        if let g = gesture {
            gestureT += dt
            let p = gestureT / g.duration
            if p >= 1 { gesture = nil } else {
                let env = sin(.pi * min(1, p)), ramp = min(1, min(p, 1 - p) * 5)
                switch g {
                case .nod: nod = sin(gestureT * 11) * 0.16 * env
                case .shake: shake = sin(gestureT * 12) * 0.3 * env
                case .jump:
                    jumpY = max(0, sin(.pi * min(1, p * 1.15))) * 0.5
                    squash = p > 0.85 ? sin(.pi * (p - 0.85) / 0.15) * 0.1 : 0
                    let up = ArmPose(z: 0.9 * ramp + 0.12, x: -0.3 * ramp, ex: -0.6 * ramp, ez: 0)
                    overrides = [up, up]
                case .wave:
                    overrides[1] = ArmPose(z: 2.5 * ramp + 0.12 * (1 - ramp), x: -0.15 * ramp, ex: 0, ez: (0.35 + sin(gestureT * 12) * 0.45) * ramp)
                case .shrug:
                    gTilt = 0.12 * ramp
                    let s = ArmPose(z: 0.6 * ramp, x: -0.55 * ramp, ex: -1.15 * ramp, ez: 0)
                    overrides = [s, s]
                }
            }
        }

        // Arms
        for i in 0..<2 {
            let side: Float = i == 0 ? -1 : 1
            let target = overrides[i] ?? (c.mood == .thinking && i == 1 ? .chin : .target(c.mood))
            armPoses[i].approach(target, 1 - exp(-dt * (overrides[i] == nil ? 7 : 18)))
            let a = armPoses[i]
            let sway = sin(t * 1.6 + side) * 0.03
            shoulders[i].orientation = euler(a.x + sway, 0, side * a.z)
            elbows[i].orientation = euler(a.ex, 0, side * a.ez)
        }

        // Body
        let laughBob: Float = c.mood == .laughing ? abs(sin(t * 9)) * 0.04 : 0
        root.position.y = jumpY + laughBob
        root.scale = [1 + squash * 0.6, 1 - squash, 1 + squash * 0.6]
        root.orientation = simd_quatf(angle: c.yaw, axis: [0, 1, 0])
        torso.orientation = euler(0, 0, sin(t * 0.9) * 0.02 - face.tilt * 0.2)
        torso.scale = [1, 1 + sin(t * 2.2) * 0.01, 1]
        for (i, hip) in hips.enumerated() { hip.orientation = euler(0, 0, (i == 0 ? -1 : 1) * 0.02 + sin(t * 0.9) * 0.01) }
        head.orientation = euler(face.pitch + nod, shake, -face.tilt - gTilt + sin(t * 0.7) * 0.02)

        // Eyes: lids close from the top; a happy squint narrows the eye from below
        let open = max(0.05, min(1.3, face.eyeOpen * (1 - blink)))
        let close = max(0, 1 - open)
        let squint = face.eyeHappy * 0.5
        for eye in eyes {
            // Blinks and squints squash the eye itself, so nothing pokes out of the head.
            let openness = max(0.06, min(1.25, open))
            if eye.lidMax > 0 {
                eye.ball.scale.y = eye.baseScale.y * openness * (1 - squint)
                eye.ball.position.y = eye.basePos.y + eye.baseScale.y * squint * 0.9
            } else {
                eye.ball.scale.y = max(0.004, eye.baseScale.y * openness * (1 - 0.6 * face.eyeHappy))
                eye.ball.position.y = eye.basePos.y + 0.015 * face.eyeHappy
            }
            eye.glint?.isEnabled = face.eyeHappy < 0.3
        }
        for b in brows {
            let lift = face.browY + (b.side < 0 ? face.browAsym : 0)
            b.entity.position = b.base + [0, lift, 0]
            b.entity.orientation = b.baseRot * simd_quatf(angle: b.side * face.browTilt, axis: [0, 0, 1])
        }

        // Mouth: voice loudness drives it when audio plays; otherwise a gentle flap while text is shown
        let voice = c.voiceLevel()
        let flap: Float = c.speaking ? 0.18 + 0.5 * abs(sin(t * 15)) * (0.65 + 0.35 * sin(t * 4.7)) : 0
        let openAmt = max(face.mouthOpen, flap, voice * 0.95)
        let curve = face.mouthCurve
        for m in mouthSides {
            m.entity.position = mouthBase + [m.side * mouthSpacing * (1 - 0.4 * face.mouthRound), curve * mouthSpacing * 0.24, -0.004]
            m.entity.orientation = simd_quatf(angle: m.side * curve * 0.45, axis: [0, 0, 1])
        }
        mouthCenter?.position = mouthBase + [0, -curve * mouthSpacing * 0.1, 0]
        mouthHole?.scale = [mouthHoleSize.x * (1 - 0.35 * face.mouthRound), max(0.001, mouthHoleSize.y * openAmt), mouthHoleSize.z]
        mouthHole?.position = mouthBase + [0, -mouthHoleSize.y * 0.47 * openAmt, -0.002]

        if !cheeks.isEmpty, abs(face.blush - shownBlush) > 0.03 {
            shownBlush = face.blush
            let m = Mat.glow(0xFF7A95, opacity: max(0.01, face.blush * 0.55))
            for ch in cheeks { ch.model?.materials = [m] }
        }
    }
}
