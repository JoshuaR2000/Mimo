import SwiftUI
import RealityKit

/// Holds the live 3D rig so the RealityView can swap characters.
@MainActor
final class StageModel {
    let anchor = Entity()
    var rig: BipedRig?
    var light: Entity?
    var subscription: EventSubscription?

    func install(_ kind: CharacterKind, palette: Palette) {
        rig?.root.removeFromParent()
        let newRig = BipedRig(kind: kind, palette: palette)
        anchor.addChild(newRig.root)
        if let light { newRig.root.applyLightReceiver(light) }
        rig = newRig
    }
}

/// The 3D character, its lights and camera. Drag sideways to turn the character.
struct CharacterStage: View {
    let controller: CharacterController
    @State private var stage = StageModel()
    @State private var dragStartYaw: Float?

    var body: some View {
        RealityView { content in
            content.add(stage.anchor)
            stage.install(controller.kind, palette: controller.palette)
            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 30
            camera.look(at: [0, 0.62, 0], from: [0, 1.0, 7.6], relativeTo: nil)
            content.add(camera)

            let sun = DirectionalLight()
            sun.light.intensity = 2600
            sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 6, depthBias: 2)
            sun.look(at: [0, 1, 0], from: [2, 5, 4], relativeTo: nil)
            content.add(sun)

            let rim = DirectionalLight()
            rim.light.color = PlatformColor(hex: 0x8A7BFF)
            rim.light.intensity = 1800
            rim.look(at: [0, 1.2, 0], from: [-3, 3, -4], relativeTo: nil)
            content.add(rim)

            if let sky = Self.makeSkyImage(), let env = try? await EnvironmentResource(equirectangular: sky) {
                let ibl = Entity()
                ibl.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: 0.4))
                content.add(ibl)
                stage.light = ibl
                stage.rig?.root.applyLightReceiver(ibl)
            }

            let stage = stage
            let controller = controller
            stage.subscription = content.subscribe(to: SceneEvents.Update.self) { event in
                MainActor.assumeIsolated {
                    stage.rig?.update(dt: Float(event.deltaTime), controller: controller)
                }
            }
        } update: { _ in
            if stage.rig?.kind != controller.kind {
                stage.install(controller.kind, palette: controller.palette)
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if dragStartYaw == nil { dragStartYaw = controller.yaw }
                    controller.yaw = (dragStartYaw ?? 0) + Float(value.translation.width) * 0.01
                }
                .onEnded { _ in dragStartYaw = nil }
        )
        .accessibilityElement()
        .accessibilityLabel("\(controller.kind.displayName), your \(controller.kind.title.lowercased()) assistant")
        .accessibilityValue("Looking \(controller.mood.label.lowercased())")
        .accessibilityHint("Drag left or right to turn the character around.")
    }

    /// A soft gradient "sky" used as image-based lighting so surfaces look glossy.
    private static func makeSkyImage() -> CGImage? {
        let w = 256, h = 128
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [CGColor(red: 0.85, green: 0.9, blue: 1.0, alpha: 1),
                      CGColor(red: 0.45, green: 0.45, blue: 0.7, alpha: 1),
                      CGColor(red: 0.08, green: 0.08, blue: 0.16, alpha: 1)] as CFArray
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.5, 1]) else { return nil }
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])
        return ctx.makeImage()
    }
}

extension Entity {
    /// Lets every model under this entity pick up the image-based light.
    func applyLightReceiver(_ light: Entity) {
        if self is ModelEntity { components.set(ImageBasedLightReceiverComponent(imageBasedLight: light)) }
        for child in children { child.applyLightReceiver(light) }
    }
}
