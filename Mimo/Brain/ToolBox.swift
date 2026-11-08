import Foundation
import EventKit
import UserNotifications
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Actions the assistant can take on the user's behalf. Each returns a short text result for the model.
@MainActor
final class ToolBox {
    private let memory: MemoryStore
    private let events = EKEventStore()

    init(memory: MemoryStore) { self.memory = memory }

    // MARK: - Definitions sent to the model

    var definitions: [[String: Any]] {
        [
            fn("set_reminder", "Create a reminder in the Reminders app.",
               ["title": str("What to be reminded about"), "due": nullableStr("Local date-time like 2026-11-09T09:00:00, or null for no due date")]),
            fn("add_calendar_event", "Add an event to the user's default calendar.",
               ["title": str("Event title"), "start": str("Local start date-time like 2026-11-09T14:00:00"), "end": nullableStr("Local end date-time, or null for one hour")]),
            fn("get_calendar_events", "List the user's calendar events for one day.",
               ["day": nullableStr("Local date like 2026-11-09, or null for today")]),
            fn("save_note", "Save a note for the user.", ["text": str("The note text")]),
            fn("list_notes", "Read the user's saved notes, newest first.", [:]),
            fn("set_timer", "Start a timer that alerts the user when it ends.",
               ["seconds": ["type": "integer", "description": "Timer length in seconds"], "label": nullableStr("What the timer is for, or null")]),
            fn("get_weather", "Current weather and today's high and low for a city.", ["city": str("City name, e.g. Austin")]),
            fn("open_maps", "Open Apple Maps to search for a place or get directions.", ["query": str("Place or address")]),
            fn("remember_fact", "Save a lasting fact about the user to long-term memory.", ["fact": str("Short fact, e.g. 'Has a dog named Max'")]),
        ]
    }

    private func fn(_ name: String, _ description: String, _ props: [String: Any]) -> [String: Any] {
        ["type": "function", "name": name, "description": description, "strict": true,
         "parameters": ["type": "object", "properties": props, "required": Array(props.keys), "additionalProperties": false] as [String: Any]]
    }
    private func str(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
    private func nullableStr(_ d: String) -> [String: Any] { ["type": ["string", "null"], "description": d] }

    // MARK: - Running tools

    func run(_ name: String, arguments: String) async -> String {
        let args = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any] ?? [:]
        do {
            switch name {
            case "set_reminder": return try await setReminder(title: args["title"] as? String ?? "Reminder", due: args["due"] as? String)
            case "add_calendar_event": return try await addEvent(title: args["title"] as? String ?? "Event", start: args["start"] as? String ?? "", end: args["end"] as? String)
            case "get_calendar_events": return try await listEvents(day: args["day"] as? String)
            case "save_note":
                let note = memory.addNote(args["text"] as? String ?? "")
                return "Saved note: \(note.text)"
            case "list_notes":
                let notes = memory.notes.prefix(15).map { "- \($0.text) (\($0.created.formatted(date: .abbreviated, time: .omitted)))" }
                return notes.isEmpty ? "There are no saved notes." : notes.joined(separator: "\n")
            case "set_timer": return try await setTimer(seconds: args["seconds"] as? Int ?? 60, label: args["label"] as? String)
            case "get_weather": return try await weather(city: args["city"] as? String ?? "")
            case "open_maps": return openMaps(args["query"] as? String ?? "")
            case "remember_fact":
                memory.remember(args["fact"] as? String ?? "")
                return "Remembered."
            default: return "Unknown tool \(name)."
            }
        } catch {
            return "Failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Reminders and calendar

    private func setReminder(title: String, due: String?) async throws -> String {
        guard try await events.requestFullAccessToReminders() else { return "Failed: the user hasn't allowed access to Reminders. They can turn it on in Settings." }
        let reminder = EKReminder(eventStore: events)
        reminder.title = title
        reminder.calendar = events.defaultCalendarForNewReminders()
        if let due, let date = Self.parseDate(due) {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            reminder.addAlarm(EKAlarm(absoluteDate: date))
        }
        try events.save(reminder, commit: true)
        return "Reminder created: \(title)" + (due.flatMap(Self.parseDate).map { " at \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")
    }

    private func addEvent(title: String, start: String, end: String?) async throws -> String {
        guard try await events.requestFullAccessToEvents() else { return "Failed: the user hasn't allowed calendar access. They can turn it on in Settings." }
        guard let startDate = Self.parseDate(start) else { return "Failed: couldn't read the start time \(start)." }
        let event = EKEvent(eventStore: events)
        event.title = title
        event.startDate = startDate
        event.endDate = end.flatMap(Self.parseDate) ?? startDate.addingTimeInterval(3600)
        event.calendar = events.defaultCalendarForNewEvents
        try events.save(event, span: .thisEvent, commit: true)
        return "Event added: \(title) on \(startDate.formatted(date: .abbreviated, time: .shortened))"
    }

    private func listEvents(day: String?) async throws -> String {
        guard try await events.requestFullAccessToEvents() else { return "Failed: the user hasn't allowed calendar access." }
        let date = day.flatMap(Self.parseDate) ?? Date()
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let found = events.events(matching: events.predicateForEvents(withStart: start, end: end, calendars: nil))
        if found.isEmpty { return "No events on \(start.formatted(date: .complete, time: .omitted))." }
        return found.map { e in
            e.isAllDay ? "- \(e.title ?? "Event") (all day)" : "- \(e.title ?? "Event") at \(e.startDate.formatted(date: .omitted, time: .shortened))"
        }.joined(separator: "\n")
    }

    // MARK: - Timer

    private func setTimer(seconds: Int, label: String?) async throws -> String {
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound]) else { return "Failed: notifications are turned off for Mimo." }
        let content = UNMutableNotificationContent()
        content.title = "Timer done"
        content.body = label ?? "Your timer has finished."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, seconds)), repeats: false)
        try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger))
        return "Timer set for \(Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide)))."
    }

    // MARK: - Weather (Open-Meteo, no key needed)

    private func weather(city: String) async throws -> String {
        guard let q = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let geoURL = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(q)&count=1") else { return "Failed: bad city name." }
        let (geoData, _) = try await URLSession.shared.data(from: geoURL)
        guard let place = ((try JSONSerialization.jsonObject(with: geoData) as? [String: Any])?["results"] as? [[String: Any]])?.first,
              let lat = place["latitude"] as? Double, let lon = place["longitude"] as? Double else { return "Couldn't find a place called \(city)." }
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code,wind_speed_10m&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=1")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let current = json["current"] as? [String: Any] ?? [:]
        let daily = json["daily"] as? [String: Any] ?? [:]
        let temp = current["temperature_2m"] as? Double ?? .nan
        let wind = current["wind_speed_10m"] as? Double ?? .nan
        let code = current["weather_code"] as? Int ?? -1
        let high = (daily["temperature_2m_max"] as? [Double])?.first ?? .nan
        let low = (daily["temperature_2m_min"] as? [Double])?.first ?? .nan
        let name = [place["name"] as? String, place["country"] as? String].compactMap { $0 }.joined(separator: ", ")
        return "\(name): \(Self.describe(code)), \(Int(temp.rounded()))°C now, high \(Int(high.rounded()))°C, low \(Int(low.rounded()))°C, wind \(Int(wind.rounded())) km/h."
    }

    private static func describe(_ code: Int) -> String {
        switch code {
        case 0: "clear sky"
        case 1, 2: "partly cloudy"
        case 3: "overcast"
        case 45, 48: "foggy"
        case 51...57: "drizzle"
        case 61...67, 80...82: "rain"
        case 71...77, 85, 86: "snow"
        case 95...99: "thunderstorms"
        default: "mixed conditions"
        }
    }

    // MARK: - Maps

    private func openMaps(_ query: String) -> String {
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "http://maps.apple.com/?q=\(q)") else { return "Failed: bad place name." }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
        return "Opened Maps for \(query)."
    }

    // MARK: - Dates

    static func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
