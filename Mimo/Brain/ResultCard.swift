import Foundation

/// A visual summary of something the assistant just did, shown under its reply.
enum ResultCard: Identifiable, Equatable {
    struct AgendaItem: Hashable { let title: String; let time: String }

    case reminder(id: String, title: String, due: Date?)
    case event(id: String, title: String, start: Date, end: Date)
    case agenda(day: Date, items: [AgendaItem])
    case weather(place: String, summary: String, symbol: String, temp: Int, high: Int, low: Int, unit: String)
    case timer(id: String, label: String, ends: Date)
    case note(id: UUID, text: String)

    var id: String {
        switch self {
        case .reminder(let id, _, _), .event(let id, _, _, _), .timer(let id, _, _): id
        case .agenda(let day, _): "agenda-\(day.timeIntervalSince1970)"
        case .weather(let place, _, _, _, _, _, _): "weather-\(place)"
        case .note(let id, _): id.uuidString
        }
    }

    /// Cards for things the assistant created can be undone.
    var canUndo: Bool {
        switch self {
        case .reminder, .event, .timer, .note: true
        case .agenda, .weather: false
        }
    }
}

extension ToolBox {
    /// What the character is doing while a tool runs, shown in the status pill.
    static func activity(for tool: String) -> String? {
        switch tool {
        case "set_reminder": "Setting a reminder"
        case "add_calendar_event": "Adding to your calendar"
        case "get_calendar_events": "Checking your calendar"
        case "save_note": "Saving a note"
        case "list_notes": "Reading your notes"
        case "set_timer": "Starting a timer"
        case "get_weather": "Looking up the weather"
        case "open_maps": "Opening Maps"
        case "remember_fact": "Remembering that"
        case "switch_character": "Getting a friend"
        default: nil
        }
    }
}
