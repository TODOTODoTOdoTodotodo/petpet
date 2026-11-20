import Foundation
import WinSDK

/// This object is responsible for the Windows readings the habitat needs each tick: pointer position,
/// time since the last keyboard or mouse input, and moving a pointer a pet is holding.
/// Key-press counting (Raw Input) and microphone use (WASAPI) come in phase 4; until then they read as none.
final class WindowsHostSenses: HostSenses {
    var cursor: CGPoint {
        var point = POINT()
        guard GetCursorPos(&point) else { return .zero }
        return WindowsCoordinates.current().point(point)
    }

    /// 마지막 입력 시각과 지금의 차이 (입력 내용은 읽지 않음)
    func secondsSinceUserInput() -> TimeInterval {
        var info = LASTINPUTINFO()
        info.cbSize = UINT(MemoryLayout<LASTINPUTINFO>.size)
        guard GetLastInputInfo(&info) else { return 0 }
        return TimeInterval(GetTickCount() &- info.dwTime) / 1000
    }

    func newKeyPresses() -> Int { 0 }

    func microphoneInUse() -> Bool { false }

    func moveCursor(to point: CGPoint) {
        let target = WindowsCoordinates.current().screenPoint(point)
        _ = SetCursorPos(target.x, target.y)
    }
}
