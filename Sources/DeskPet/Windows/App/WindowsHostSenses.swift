import DeskPetAudio
import Foundation
import WinSDK

/// This object is responsible for the Windows readings the habitat needs each tick: pointer position,
/// time since the last keyboard or mouse input, how many keys were pressed (counts only, from `RawKeyCounter`),
/// whether a microphone is in use (WASAPI sessions, never audio), and moving a pointer a pet is holding.
final class WindowsHostSenses: HostSenses {
    private let keys: RawKeyCounter
    /// 마이크 확인 횟수와 마지막 결과 (연기 시험 보고서용)
    private(set) var microphoneChecks = 0
    private(set) var lastMicrophone: (inUse: Int32, devices: Int32) = (-1, 0)

    init(keys: RawKeyCounter) {
        self.keys = keys
    }

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

    func newKeyPresses() -> Int { keys.newPresses() }

    /// 녹음 세션이 활성인 마이크가 있는지 (확인하지 못하면 아님으로 봄)
    func microphoneInUse() -> Bool {
        var devices: Int32 = 0
        let inUse = dp_microphone_in_use(&devices)
        microphoneChecks += 1
        lastMicrophone = (inUse, devices)
        return inUse == 1
    }

    func moveCursor(to point: CGPoint) {
        let target = WindowsCoordinates.current().screenPoint(point)
        _ = SetCursorPos(target.x, target.y)
    }
}
