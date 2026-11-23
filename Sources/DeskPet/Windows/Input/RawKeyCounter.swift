import Foundation
import WinSDK

/// This object is responsible for counting key presses on Windows for the typing reaction, the way the macOS
/// session key-down counter does: Raw Input delivers keyboard events to the hidden app window even while other
/// apps have focus (`RIDEV_INPUTSINK`), and only whether a key went down is read. Which key it was and what was typed
/// is never looked at or kept. It listens only while the typing reaction is on.
final class RawKeyCounter {
    // winuser.h 값 (매크로라 Swift로 들여와지지 않을 수 있어 직접 적음)
    private static let genericDesktop: USHORT = 0x01 // HID_USAGE_PAGE_GENERIC
    private static let keyboard: USHORT = 0x06 // HID_USAGE_GENERIC_KEYBOARD
    private static let inputSink: DWORD = 0x0000_0100 // RIDEV_INPUTSINK
    private static let remove: DWORD = 0x0000_0001 // RIDEV_REMOVE
    private static let rawInput: UINT = 0x1000_0003 // RID_INPUT
    private static let keyboardType: DWORD = 1 // RIM_TYPEKEYBOARD
    private static let keyBreak: USHORT = 0x01 // RI_KEY_BREAK (키를 뗌)

    private let window: HWND
    private var pending = 0
    /// 켠 뒤 센 모든 누름 (연기 시험 보고서용)
    private(set) var total = 0
    private(set) var isListening = false

    init(window: HWND) {
        self.window = window
    }

    /// 듣기 켜기·끄기 (설정의 타이핑 반응). 성공하면 true
    @discardableResult
    func listen(_ on: Bool) -> Bool {
        guard on != isListening else { return true }
        var device = RAWINPUTDEVICE(usUsagePage: Self.genericDesktop, usUsage: Self.keyboard,
                                    dwFlags: on ? Self.inputSink : Self.remove, hwndTarget: on ? window : nil)
        guard RegisterRawInputDevices(&device, 1, UINT(MemoryLayout<RAWINPUTDEVICE>.size)) else {
            WindowsLogger.shared.log("⚠️ key-press counter could not \(on ? "start" : "stop") (error \(GetLastError()))")
            return false
        }
        isListening = on
        pending = 0
        WindowsLogger.shared.log(on ? "⌨️ key-press counter on (counts only)" : "⌨️ key-press counter off")
        return true
    }

    /// WM_INPUT 하나를 읽어 키를 누른 것이면 셈 (떼기·마우스는 무시). 처리 뒤 기본 처리로 넘겨야 함
    func receive(_ lParam: LPARAM) {
        guard isListening, let handle = HRAWINPUT(bitPattern: Int(lParam)) else { return }
        var input = RAWINPUT()
        var size = UINT(MemoryLayout<RAWINPUT>.size)
        let header = UINT(MemoryLayout<RAWINPUTHEADER>.size)
        guard GetRawInputData(handle, Self.rawInput, &input, &size, header) != UINT.max,
              input.header.dwType == Self.keyboardType else { return }
        // 읽는 것은 누름·뗌 표시뿐 (어떤 키인지는 보지 않음)
        if input.data.keyboard.Flags & Self.keyBreak == 0 {
            pending += 1
            total += 1
        }
    }

    /// 지난번 뒤 새로 누른 수
    func newPresses() -> Int {
        defer { pending = 0 }
        return pending
    }
}
