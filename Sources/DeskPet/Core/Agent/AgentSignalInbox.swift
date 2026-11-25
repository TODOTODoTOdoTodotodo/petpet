import Foundation

/// This object is responsible for the inbox folder AI coding tools drop signals into through their hooks
/// (`~/.deskpet/signals/*.json`, the same path on macOS and Windows): every second it takes each new file, deletes it,
/// and reports the signal. Stale, oversized or unreadable files are deleted without being reported.
final class AgentSignalInbox {
    static let interval: TimeInterval = 1
    /// 홈 폴더의 `.deskpet/signals` (훅 한 줄을 맥·윈도우 Git Bash에서 그대로 쓰려고 공백 없는 경로)
    static var homeFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".deskpet/signals", isDirectory: true)
    }

    var onSignal: ((AgentSignal) -> Void)?
    private let folder: URL
    private var timer: Timer?

    /// folder: 받은 편지함 폴더 (검사에서는 임시 폴더)
    init(folder: URL) {
        self.folder = folder
    }

    func start() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // 앱이 꺼져 있던 동안 쌓인 신호는 오래된 것으로 버림
        check()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// .json만 읽음 (쓰는 중인 .tmp·숨은 파일은 건너뜀). 읽은 파일은 바로 지움
    func check(now: Date = Date()) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                        options: [.skipsHiddenFiles]) else { return }
        let signals = files.filter { $0.pathExtension == "json" }.compactMap { file -> (Date, AgentSignal)? in
            defer { try? FileManager.default.removeItem(at: file) }
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  (values.fileSize ?? .max) <= AgentSignal.maxBytes,
                  let modified = values.contentModificationDate, now.timeIntervalSince(modified) <= AgentSignal.maxAge,
                  let data = try? Data(contentsOf: file), let signal = AgentSignal.parse(data) else { return nil }
            return (modified, signal)
        }
        signals.sorted { $0.0 < $1.0 }.forEach { onSignal?($0.1) }
    }
}
