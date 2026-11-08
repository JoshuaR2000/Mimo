import SwiftUI

/// Shows what the assistant just did, with Undo where it makes sense.
struct ResultCardView: View {
    let card: ResultCard
    let accent: Color
    let onUndo: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch card {
        case .reminder(_, let title, let due):
            confirmation(kind: "Reminder set", icon: "checkmark", title: title,
                         detail: due.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "No due time",
                         openTitle: "Open Reminders", openURL: URL(string: "x-apple-reminderkit://"))
        case .event(_, let title, let start, let end):
            confirmation(kind: "Added to calendar", icon: "calendar", title: title,
                         detail: "\(start.formatted(date: .abbreviated, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))",
                         openTitle: "Open Calendar", openURL: URL(string: "calshow:\(start.timeIntervalSinceReferenceDate)"))
        case .timer(_, let label, let ends):
            confirmation(kind: "Timer running", icon: "timer", title: label, detail: nil, openTitle: nil, openURL: nil) {
                Text(timerInterval: Date.now...max(Date.now, ends), countsDown: true)
                    .font(Brand.display(.title2, weight: .bold)).monospacedDigit()
            }
        case .note(_, let text):
            confirmation(kind: "Note saved", icon: "note.text", title: text, detail: nil, openTitle: nil, openURL: nil)
        case .agenda(let day, let items):
            agenda(day: day, items: items)
        case .weather(let place, let summary, let symbol, let temp, let high, let low, let unit):
            weather(place: place, summary: summary, symbol: symbol, temp: temp, high: high, low: low, unit: unit)
        }
    }

    // Light card: something was created, so it can be undone or opened.
    private func confirmation(kind: String, icon: String, title: String, detail: String?, openTitle: String?, openURL url: URL?,
                              @ViewBuilder extra: () -> some View = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Brand.violet, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.uppercased()).font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(Color(hex: 0x5B4FA0))
                    Text(title).font(Brand.display(.title3)).foregroundStyle(Brand.ink).lineLimit(2)
                    if let detail { Text(detail).font(.subheadline).foregroundStyle(Color(hex: 0x4A4570)) }
                }
                Spacer(minLength: 0)
                extra().foregroundStyle(Brand.ink)
            }
            HStack(spacing: 8) {
                Button(action: onUndo) {
                    Text("Undo").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xCFC8F2), lineWidth: 1))
                        .foregroundStyle(Brand.ink)
                }
                .buttonStyle(.plain)
                if let openTitle, let url {
                    Button { openURL(url) } label: {
                        Text(openTitle).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                            .background(Brand.ink, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Brand.mist, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
    }

    private func agenda(day: Date, items: [ResultCard.AgendaItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(day.formatted(.dateTime.weekday(.wide).month().day()).uppercased())
                .font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(Brand.lavender)
            if items.isEmpty {
                Text("Nothing scheduled").font(.body).foregroundStyle(Brand.mist)
            }
            ForEach(Array(items.prefix(5).enumerated()), id: \.offset) { index, item in
                HStack(spacing: 12) {
                    Capsule().fill(index.isMultiple(of: 2) ? Color(hex: 0x4FE3F0) : Color(hex: 0xFF8A6B)).frame(width: 4, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.body.weight(.semibold)).foregroundStyle(Brand.mist)
                        Text(item.time).font(.footnote).foregroundStyle(Brand.lavender)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Brand.deep, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Brand.indigo, lineWidth: 1))
    }

    private func weather(place: String, summary: String, symbol: String, temp: Int, high: Int, low: Int, unit: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 40))
                .frame(width: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.uppercased()).font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(Brand.lavender)
                Text(summary).font(Brand.display(.title3)).foregroundStyle(Brand.mist)
                Text("High \(high)\(unit) · Low \(low)\(unit)").font(.footnote).foregroundStyle(Brand.lavender)
            }
            Spacer(minLength: 0)
            Text("\(temp)\(unit)").font(Brand.display(.largeTitle, weight: .bold)).foregroundStyle(Brand.mist)
        }
        .padding(16)
        .background(Brand.deep, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Brand.indigo, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
