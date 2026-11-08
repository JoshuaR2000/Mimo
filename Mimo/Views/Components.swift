import SwiftUI

/// The character's speech: a bubble with a tail pointing up at it and its name in its accent color.
struct SpeechBubble: View {
    let name: String
    let accent: Color
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Brand.dusk)
                .frame(width: 18, height: 18)
                .rotationEffect(.degrees(45))
                .offset(y: 9)
                .zIndex(1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(name.uppercased())
                    .font(Brand.display(.caption, weight: .bold)).tracking(0.8)
                    .foregroundStyle(accent)
                Text(text)
                    .font(.body)
                    .foregroundStyle(Brand.mist)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(Brand.dusk, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Brand.indigo, lineWidth: 1))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) says: \(text)")
    }
}

/// What the user said, aligned to the right in the brand violet.
struct UserBubble: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(Brand.violet, in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20))
            .frame(maxWidth: 300, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel("You said: \(text)")
    }
}

/// Shows what the assistant is doing right now.
struct StatusPill: View {
    let text: String
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(accent)
            Text(text).font(.subheadline.weight(.medium)).foregroundStyle(Brand.mist)
            TimelineView(.periodic(from: .now, by: reduceMotion ? 3600 : 0.35)) { context in
                let step = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().fill(accent).frame(width: 6, height: 6).opacity(i == step ? 1 : 0.3)
                    }
                }
            }
        }
        .padding(.horizontal, 18).frame(height: 44)
        .background(Brand.dusk, in: Capsule())
        .overlay(Capsule().stroke(Brand.indigo, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private var icon: String {
        let t = text.lowercased()
        if t.contains("calendar") { return "calendar" }
        if t.contains("reminder") { return "checklist" }
        if t.contains("weather") { return "cloud.sun" }
        if t.contains("note") { return "note.text" }
        if t.contains("timer") { return "timer" }
        if t.contains("map") { return "map" }
        if t.contains("search") { return "magnifyingglass" }
        return "sparkles"
    }
}

/// What state the big mic button is in.
enum MicState { case idle, listening, thinking, speaking }

/// The hero button: tap to talk, tap again to send, tap to stop the character.
struct MicButton: View {
    let state: MicState
    let level: Float
    let accent: Color
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var spin = false

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                ZStack {
                    ring
                    Circle()
                        .fill(state == .idle || state == .listening ? Brand.violet : Brand.dusk)
                        .frame(width: 84, height: 84)
                    content
                }
                .frame(width: 112, height: 112)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            Text(caption).font(.footnote).foregroundStyle(Brand.lavender)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true }
        }
    }

    @ViewBuilder private var ring: some View {
        switch state {
        case .idle:
            Circle().stroke(Brand.violetRing, lineWidth: 2)
                .frame(width: 106, height: 106)
                .scaleEffect(pulse ? 1.05 : 1)
                .opacity(pulse ? 0.6 : 1)
        case .listening:
            Circle().stroke(Brand.violet.opacity(0.7), lineWidth: 3)
                .frame(width: 106, height: 106)
                .scaleEffect(1 + CGFloat(level) * 0.12)
                .animation(.linear(duration: 0.08), value: level)
        case .thinking:
            ZStack {
                Circle().stroke(Brand.outline, lineWidth: 3)
                Circle().trim(from: 0, to: 0.28).stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
            }
            .frame(width: 106, height: 106)
        case .speaking:
            Circle().stroke(accent.opacity(0.8), lineWidth: 3)
                .frame(width: 106, height: 106)
                .scaleEffect(pulse ? 1.04 : 0.98)
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle:
            Image(systemName: "mic.fill").font(.system(size: 32, weight: .semibold)).foregroundStyle(.white)
        case .listening:
            HStack(spacing: 5) {
                ForEach(0..<5, id: \.self) { i in
                    let shape: [CGFloat] = [0.5, 0.8, 1, 0.8, 0.5]
                    Capsule().fill(.white)
                        .frame(width: 5, height: 8 + 30 * CGFloat(level) * shape[i])
                }
            }
            .animation(.linear(duration: 0.08), value: level)
        case .thinking, .speaking:
            RoundedRectangle(cornerRadius: 6).fill(Brand.mist).frame(width: 24, height: 24)
        }
    }

    private var caption: String {
        switch state {
        case .idle: "Tap to talk"
        case .listening: "Listening… tap to send"
        case .thinking: "Thinking… tap to stop"
        case .speaking: "Tap to stop"
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle: "Talk"
        case .listening: "Send what you said"
        case .thinking, .speaking: "Stop"
        }
    }
}

/// Starter ideas shown when the conversation is quiet.
struct SuggestionChips: View {
    let suggestions: [String]
    let onPick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button { onPick(s) } label: {
                        Text(s).font(.subheadline.weight(.medium)).foregroundStyle(Color(hex: 0xE4DCFF))
                            .padding(.horizontal, 14).frame(minHeight: 40)
                            .overlay(Capsule().stroke(Brand.indigo, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}
