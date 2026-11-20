import Foundation

/// This object is responsible for checking the schedule every 30 seconds (and whenever calendar data changes)
/// and handing new announcements to the pets.
final class ScheduleWatcher {
    private let source: ScheduleSource
    private let announcer: ScheduleAnnouncer
    private let speak: (ScheduleNotice) -> Void
    private var timer: Timer?

    static let checkInterval: TimeInterval = 30

    init(source: ScheduleSource, announcer: ScheduleAnnouncer, speak: @escaping (ScheduleNotice) -> Void) {
        self.source = source
        self.announcer = announcer
        self.speak = speak
    }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            self?.check()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        check()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 지금 말할 일정을 찾아 펫에게 넘김
    func check(at now: Date = Date()) {
        guard isRunning else { return }
        // 10분 전 알림까지 잡도록 앞쪽 범위를 넉넉히 둠
        let items = source.items(from: now.addingTimeInterval(-ScheduleAnnouncer.freshness),
                                 to: now.addingTimeInterval(ScheduleAnnouncer.leadTime + ScheduleAnnouncer.freshness))
        announcer.announcements(for: items, at: now).forEach(speak)
    }
}
