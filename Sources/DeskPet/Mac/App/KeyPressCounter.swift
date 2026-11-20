import CoreGraphics

/// This object is responsible for telling how many keys were pressed since it was last asked, using the system's
/// running key-down count for the login session. It never sees which keys were pressed or what was typed.
final class KeyPressCounter {
    private var last: UInt32?

    /// 지금까지 누른 수 (로그인 세션 전체)
    static func total() -> UInt32 {
        CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
    }

    /// 지난번 뒤 새로 누른 수. 처음 물으면 0
    func newPresses() -> Int {
        let now = Self.total()
        defer { last = now }
        guard let last else { return 0 }
        // 카운터가 넘쳐 되돌아가도 차이는 맞게
        return Int(now &- last)
    }
}
