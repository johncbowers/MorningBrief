import Foundation
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(secondsFromGMT: 0)!
let now = ISO8601DateFormatter().date(from: "2026-11-05T13:00:00Z")!
let rules = BriefingRules(pattern: "briefing-{date}*.md", dateFormat: "yyyy-MM-dd", useModificationDate: false)
func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message) }
check(rules.matches(URL(fileURLWithPath: "/briefing-2026-11-05-final.md"), modified: now, now: now, calendar: cal), "today matches")
check(!rules.matches(URL(fileURLWithPath: "/briefing-2026-11-04.md"), modified: now, now: now, calendar: cal), "yesterday excluded")
check(!rules.matches(URL(fileURLWithPath: "/briefing-2026-11-05.md.exe"), modified: now, now: now, calendar: cal), "non markdown excluded")
let fixed = BriefingRules(pattern: "summary.md", dateFormat: "yyyy-MM-dd", useModificationDate: true)
check(!fixed.matches(URL(fileURLWithPath: "/summary.md"), modified: now.addingTimeInterval(-86400), now: now, calendar: cal), "stale fixed file excluded")
func eligible(_ last: String = "", _ available: Bool = true, _ unlocked: Bool = true, _ start: Int = 8, _ end: Int = 15) -> Bool {
    BriefingRules.shouldOpen(now: now, start: start, end: end, lastDay: last, available: available, enabled: true, unlocked: unlocked, calendar: cal)
}
check(eligible(), "late arrival eligible")
check(!eligible(BriefingRules.dayKey(now, calendar: cal)), "once per day")
check(!eligible("", false), "missing file")
check(!eligible("", true, false), "locked")
check(!eligible("", true, true, 14), "before start")
check(!eligible("", true, true, 8, 13), "cutoff exclusive")
check(eligible("2026-11-4"), "new day")
let actual = BriefingRules(pattern: "{date}.md", dateFormat: "yyyy-MM-dd", useModificationDate: false)
check(actual.matches(URL(fileURLWithPath: "/2026-11-05.md"), modified: now, now: now, calendar: cal), "actual daily convention")
check(!actual.matches(URL(fileURLWithPath: "/2026-11-05-review.md"), modified: now, now: now, calendar: cal), "reviews excluded")
print("Passed 13 matching and morning policy checks")
