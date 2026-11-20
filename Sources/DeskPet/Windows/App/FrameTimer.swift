import Foundation
import WinSDK

/// This object is responsible for a steady frame clock on Windows: a periodic high-resolution waitable timer
/// (Windows 10 1803+, plain waitable timer before that) waited on together with window messages,
/// so the message loop wakes for whichever comes first.
final class FrameTimer {
    // synchapi.h·winuser.h의 값 (매크로 조합이라 Swift로 들여와지지 않을 수 있어 직접 적음)
    private static let highResolution: DWORD = 0x0000_0002 // CREATE_WAITABLE_TIMER_HIGH_RESOLUTION
    private static let timerAllAccess: DWORD = 0x001F_0003 // TIMER_ALL_ACCESS
    private static let allInput: DWORD = 0x0000_04FF // QS_ALLINPUT
    private static let inputAvailable: DWORD = 0x0000_0004 // MWMO_INPUTAVAILABLE

    private let handle: HANDLE?

    init(milliseconds: Int32) {
        handle = CreateWaitableTimerExW(nil, nil, Self.highResolution, Self.timerAllAccess)
            ?? CreateWaitableTimerExW(nil, nil, 0, Self.timerAllAccess)
        var due = LARGE_INTEGER()
        // 100ns 단위, 음수는 지금부터의 상대 시간
        due.QuadPart = -Int64(milliseconds) * 10_000
        if let handle {
            _ = SetWaitableTimer(handle, &due, milliseconds, nil, nil, false)
        }
    }

    deinit {
        if let handle { _ = CloseHandle(handle) }
    }

    /// 다음 틱이나 메시지가 올 때까지 기다림. 틱이면 true
    func waitForTickOrMessage() -> Bool {
        guard let handle else {
            // 타이머를 못 만들면 메시지만 기다리며 16ms마다 깸
            _ = MsgWaitForMultipleObjectsEx(0, nil, 16, Self.allInput, Self.inputAvailable)
            return true
        }
        var handles: [HANDLE?] = [handle]
        let result = MsgWaitForMultipleObjectsEx(1, &handles, DWORD.max, Self.allInput, Self.inputAvailable)
        return result == 0 // WAIT_OBJECT_0
    }
}
