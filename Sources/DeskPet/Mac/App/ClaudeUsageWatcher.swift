import Foundation

/// This object is responsible for reading, every 30 seconds, the small usage file the Claude Code status line writes
/// (`~/Library/Application Support/DeskPet/claude-usage.json`) and reporting the snapshot.
/// It never talks to Anthropic servers or reads credentials; without the file it reports nil.
final class ClaudeUsageWatcher {
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/DeskPet/claude-usage.json")
    static let interval: TimeInterval = 30

    var onChange: ((ClaudeUsage?) -> Void)?
    private var timer: Timer?
    private(set) var latest: ClaudeUsage?

    func start() {
        check()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 파일을 다시 읽음. 같은 내용이어도 초기화 시각이 지났을 수 있어 매번 알림
    func check() {
        latest = (try? Data(contentsOf: Self.fileURL)).flatMap(ClaudeUsage.parse)
        onChange?(latest)
    }
}
