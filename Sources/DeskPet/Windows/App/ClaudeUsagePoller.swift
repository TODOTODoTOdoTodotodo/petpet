import Foundation

/// This object is responsible for reading, every 30 seconds on the app's tick, the small usage file the Claude Code
/// status line writes on Windows (`%APPDATA%\DeskPet\claude-usage.json`, the same fields as on macOS) and reporting
/// the snapshot. It never talks to Anthropic servers or reads credentials; without the file it reports nil.
final class ClaudeUsagePoller {
    static let interval: TimeInterval = 30
    static var fileURL: URL { WindowsPaths.data.appendingPathComponent("claude-usage.json") }

    var onChange: ((ClaudeUsage?) -> Void)?
    private(set) var latest: ClaudeUsage?
    private var lastCheck: TimeInterval?

    /// 틱마다 부름. 30초가 지났으면 다시 읽음 (처음 부르면 바로)
    func poll(now: TimeInterval) {
        if let lastCheck, now - lastCheck < Self.interval { return }
        lastCheck = now
        check()
    }

    /// 파일을 다시 읽음. 같은 내용이어도 초기화 시각이 지났을 수 있어 매번 알림
    func check() {
        latest = (try? Data(contentsOf: Self.fileURL)).flatMap(ClaudeUsage.parse)
        onChange?(latest)
    }
}
