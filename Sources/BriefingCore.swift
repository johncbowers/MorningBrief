import Foundation

struct BriefingRules {
    var pattern: String
    var dateFormat: String
    var useModificationDate: Bool
    func matches(_ url: URL, modified: Date, now: Date, calendar: Calendar = .current) -> Bool {
        guard ["md", "markdown"].contains(url.pathExtension.lowercased()) else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = dateFormat
        let expanded = pattern.replacingOccurrences(of: "{date}", with: formatter.string(from: now))
        let regex = "^" + expanded.components(separatedBy: "*").map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: ".*") + "$"
        return url.lastPathComponent.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil && (!useModificationDate || calendar.isDate(modified, inSameDayAs: now))
    }
    static func dayKey(_ now: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }
    static func shouldOpen(now: Date, start: Int, end: Int, lastDay: String, available: Bool, enabled: Bool, unlocked: Bool, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: now)
        return enabled && unlocked && available && hour >= start && hour < end && lastDay != dayKey(now, calendar: calendar)
    }
}
