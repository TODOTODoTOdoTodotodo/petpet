import Foundation

/// 한도 창 하나 (사용률 0~100, 초기화 시각)
struct UsageWindow: Equatable {
    let usedPercent: Double
    let resetsAt: Date
}

/// This object is responsible for the Claude plan usage snapshot that the Claude Code status line leaves behind
/// (the documented `rate_limits` fields only) and for how much of it still counts at a given moment.
struct ClaudeUsage: Equatable {
    var fiveHour: UsageWindow?
    var sevenDay: UsageWindow?

    /// 상태줄이 남긴 JSON: {"five_hour": {"used_percentage", "resets_at"}, "seven_day": {...}}
    static func parse(_ data: Data) -> ClaudeUsage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let usage = ClaudeUsage(fiveHour: window(json["five_hour"]), sevenDay: window(json["seven_day"]))
        return usage.fiveHour == nil && usage.sevenDay == nil ? nil : usage
    }

    /// 아직 초기화되지 않은 창 중 가장 많이 쓴 비율. 모두 지났으면 nil
    func effectivePercent(at now: Date) -> Double? {
        [fiveHour, sevenDay].compactMap { $0 }.filter { $0.resetsAt > now }.map(\.usedPercent).max()
    }

    /// 메뉴 표시용 짧은 요약. 모두 초기화됐으면 nil (문구는 메뉴 언어로 메뉴가 정함)
    func summary(at now: Date) -> String? {
        let parts = [("5h", fiveHour), ("7d", sevenDay)].compactMap { label, window -> String? in
            guard let window, window.resetsAt > now else { return nil }
            return "\(label) \(Int(window.usedPercent.rounded()))%"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func window(_ value: Any?) -> UsageWindow? {
        guard let table = value as? [String: Any],
              let used = (table["used_percentage"] as? NSNumber)?.doubleValue,
              let resets = (table["resets_at"] as? NSNumber)?.doubleValue else { return nil }
        return UsageWindow(usedPercent: min(max(used, 0), 100), resetsAt: Date(timeIntervalSince1970: resets))
    }
}
