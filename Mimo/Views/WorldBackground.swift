import SwiftUI

/// Each character lives somewhere: Zuri inside a saucer, Bolt in a workshop, Ava in a room
/// whose window follows the real time of day. Drawn behind the 3D stage.
struct WorldBackground: View {
    let kind: CharacterKind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Brand.night
            RadialGradient(colors: [glow.opacity(0.55), Brand.deep.opacity(0.6), Brand.night],
                           center: UnitPoint(x: 0.5, y: 0.38), startRadius: 10, endRadius: 360)
            GeometryReader { geo in
                switch kind {
                case .alien: saucer(geo.size)
                case .robot: workshop(geo.size)
                case .human: room(geo.size)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var glow: Color {
        switch kind {
        case .alien: Color(hex: 0x2A2160)
        case .robot: Color(hex: 0x123A4A)
        case .human: Color(hex: 0x4A2448)
        }
    }

    // MARK: Zuri — inside a flying saucer

    private func saucer(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            // Porthole with twinkling stars and a little planet
            TimelineView(.periodic(from: .now, by: reduceMotion ? 3600 : 0.6)) { context in
                let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.6)
                ZStack {
                    Circle().fill(Color(hex: 0x070615))
                    ForEach(0..<9, id: \.self) { i in
                        let p = Self.stars[i]
                        Circle().fill(.white)
                            .frame(width: p.2, height: p.2)
                            .opacity((phase + i) % 4 == 0 ? 0.35 : 1)
                            .position(x: p.0, y: p.1)
                    }
                    Circle().fill(CharacterKind.alien.accentColor.opacity(0.85))
                        .frame(width: 18, height: 18)
                        .position(x: 62, y: 66)
                }
                .frame(width: 104, height: 104)
                .clipShape(Circle())
                .overlay(Circle().stroke(Brand.outline, lineWidth: 7))
            }
            .position(x: size.width - 70, y: 210)

            // Wall panels and status lights
            VStack(alignment: .leading, spacing: 8) {
                Capsule().fill(Brand.outline).frame(width: 56, height: 6)
                Capsule().fill(Color(hex: 0x4FE3F0, opacity: 0.55)).frame(width: 34, height: 6)
                Capsule().fill(Brand.outline).frame(width: 44, height: 6)
            }
            .position(x: 52, y: 230)

            // Curved floor of the saucer
            Ellipse().fill(Brand.deep.opacity(0.9))
                .frame(width: size.width * 1.6, height: 260)
                .position(x: size.width / 2, y: size.height * 0.80)
        }
    }

    private static let stars: [(CGFloat, CGFloat, CGFloat)] = [
        (20, 26, 3), (56, 16, 2), (78, 40, 3), (30, 70, 2), (86, 82, 2), (14, 50, 2), (46, 92, 3), (70, 24, 2), (36, 40, 2),
    ]

    // MARK: Bolt — a tidy workshop

    private func workshop(_ size: CGSize) -> some View {
        ZStack {
            // Server rack with blinking lights
            TimelineView(.periodic(from: .now, by: reduceMotion ? 3600 : 0.5)) { context in
                let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.5)
                VStack(spacing: 10) {
                    ForEach(0..<6, id: \.self) { row in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(Brand.outline).frame(width: 34, height: 8)
                            Circle().fill((phase + row) % 3 == 0 ? Color(hex: 0x4FE3F0) : Color(hex: 0x1E5560))
                                .frame(width: 6, height: 6)
                            Circle().fill((phase + row * 2) % 5 == 0 ? Color(hex: 0xFF8A6B) : Brand.outline)
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                .padding(12)
                .background(Brand.deep, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.outline, lineWidth: 1))
            }
            .position(x: 54, y: size.height * 0.28)

            // Floating hologram rings
            ZStack {
                Ellipse().stroke(Color(hex: 0x4FE3F0, opacity: 0.35), lineWidth: 2).frame(width: 78, height: 26)
                Ellipse().stroke(Color(hex: 0x4FE3F0, opacity: 0.2), lineWidth: 2).frame(width: 58, height: 18).offset(y: -14)
                Image(systemName: "gearshape.2")
                    .font(.system(size: 22)).foregroundStyle(Color(hex: 0x4FE3F0, opacity: 0.55))
                    .offset(y: -30)
            }
            .position(x: size.width - 64, y: size.height * 0.22)

            // Grid floor
            Path { p in
                let top = size.height * 0.66
                for i in 0...10 {
                    let x = size.width * CGFloat(i) / 10
                    p.move(to: CGPoint(x: size.width / 2 + (x - size.width / 2) * 0.35, y: top))
                    p.addLine(to: CGPoint(x: x * 1.6 - size.width * 0.3, y: size.height))
                }
                for j in 0..<6 {
                    let t = CGFloat(j) / 5
                    let y = top + (size.height - top) * t * t
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            .stroke(Color(hex: 0x4FE3F0, opacity: 0.12), lineWidth: 1)
        }
    }

    // MARK: Ava — a cozy room with a real-time window

    private func room(_ size: CGSize) -> some View {
        let sky = Self.sky(for: Date())
        return ZStack {
            // Window
            ZStack {
                LinearGradient(colors: sky.colors, startPoint: .top, endPoint: .bottom)
                if let body = sky.body {
                    Circle().fill(body.color).frame(width: body.size, height: body.size).offset(x: 18, y: -16)
                }
                Rectangle().fill(Color(hex: 0x3A2440)).frame(width: 5)
                Rectangle().fill(Color(hex: 0x3A2440)).frame(height: 5)
            }
            .frame(width: 112, height: 136)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0x3A2440), lineWidth: 8))
            .position(x: size.width - 76, y: 220)

            // Lamp with warm glow
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(hex: 0xFFB36B, opacity: 0.35), .clear], center: .center, startRadius: 4, endRadius: 110))
                    .frame(width: 220, height: 220)
                VStack(spacing: 0) {
                    Trapezoid().fill(Color(hex: 0xFFB36B)).frame(width: 46, height: 30)
                    Rectangle().fill(Color(hex: 0x3A2440)).frame(width: 4, height: 70)
                    Capsule().fill(Color(hex: 0x3A2440)).frame(width: 34, height: 6)
                }
            }
            .position(x: 50, y: size.height * 0.36)

            // Rug
            Ellipse().fill(Color(hex: 0x3A2440, opacity: 0.8))
                .frame(width: size.width * 1.4, height: 220)
                .position(x: size.width / 2, y: size.height * 0.82)
        }
    }

    private struct Sky { let colors: [Color]; let body: (color: Color, size: CGFloat)? }

    private static func sky(for date: Date) -> Sky {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 6..<9: return Sky(colors: [Color(hex: 0xFFC48A), Color(hex: 0xFF8FA8)], body: (Color(hex: 0xFFF1C1), 26))
        case 9..<17: return Sky(colors: [Color(hex: 0x6EC6FF), Color(hex: 0xBDE6FF)], body: (Color(hex: 0xFFE680), 24))
        case 17..<20: return Sky(colors: [Color(hex: 0xFF8A6B), Color(hex: 0x7B5CFF)], body: (Color(hex: 0xFFC48A), 26))
        default: return Sky(colors: [Color(hex: 0x0B1030), Color(hex: 0x24204A)], body: (Color(hex: 0xF4F2FF), 18))
        }
    }
}

private struct Trapezoid: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX + r.width * 0.22, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - r.width * 0.22, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        }
    }
}
