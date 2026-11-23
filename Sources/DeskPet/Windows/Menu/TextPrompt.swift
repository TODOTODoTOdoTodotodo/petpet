import Foundation
import WinSDK

/// This object is responsible for the small modal text-entry window naming a pet needs on Windows (macOS uses
/// an `NSAlert` with a text field): a message, one edit field with the current text selected, and save and cancel
/// buttons, with Enter and Esc working as in a dialog box. While it is open it runs its own message loop and keeps
/// the pets moving with the same tick timer the menus use.
final class TextPrompt {
    static let windowClass = "DeskPetPrompt"
    /// 입력 칸의 컨트롤 ID (연기 시험이 찾아 씀)
    static let editID: Int32 = 100
    private static let saveID: Int32 = 1 // IDOK
    private static let cancelID: Int32 = 2 // IDCANCEL
    private static var isRegistered = false
    /// 창 프로시저가 찾아오는 열린 입력 창 (C 콜백은 문맥을 잡을 수 없음)
    private static var current: TextPrompt?

    private var typed: String?
    private var isFinished = false
    private var edit: HWND?

    /// 저장을 누르면 입력한 글, 취소·닫기면 nil. host: 열린 동안 틱 타이머를 받을 앱 창
    static func ask(title: String, message: String, initial: String, save: String, cancel: String, host: HWND) -> String? {
        guard current == nil, register() else { return nil }
        let prompt = TextPrompt()
        current = prompt
        defer { current = nil }
        return prompt.run(title: title, message: message, initial: initial, save: save, cancel: cancel, host: host)
    }

    private static func register() -> Bool {
        guard !isRegistered else { return true }
        let instance = GetModuleHandleW(nil)
        let name = windowClass.wide
        let atom = name.withUnsafeBufferPointer { pointer -> ATOM in
            var windowClass = WNDCLASSEXW()
            windowClass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
            windowClass.lpfnWndProc = { window, message, wParam, lParam in
                if let result = TextPrompt.current?.handle(message, wParam) { return result }
                return DefWindowProcW(window, message, wParam, lParam)
            }
            windowClass.hInstance = instance
            windowClass.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512))
            // 대화 상자 바탕색 (COLOR_BTNFACE + 1)
            windowClass.hbrBackground = HBRUSH(bitPattern: UInt(COLOR_BTNFACE + 1))
            windowClass.lpszClassName = pointer.baseAddress
            return RegisterClassExW(&windowClass)
        }
        isRegistered = atom != 0
        return isRegistered
    }

    private func handle(_ message: UINT, _ wParam: WPARAM) -> LRESULT? {
        switch message {
        case UINT(WM_COMMAND):
            switch Int32(truncatingIfNeeded: wParam & 0xFFFF) {
            case Self.saveID:
                typed = edit.map(Self.text(of:)) ?? ""
                isFinished = true
            case Self.cancelID:
                isFinished = true
            default:
                return nil
            }
        case UINT(WM_CLOSE):
            isFinished = true
        case UINT(WM_USER): // DM_GETDEFID: Enter는 저장 (DC_HASDEFID << 16 | IDOK)
            return LRESULT(0x534B << 16 | Int(Self.saveID))
        default:
            return nil
        }
        return 0
    }

    private func run(title: String, message: String, initial: String, save: String, cancel: String, host: HWND) -> String? {
        let instance = GetModuleHandleW(nil)
        let dpi = GetDpiForSystem()
        func scaled(_ value: Int32) -> Int32 { Int32(MulDiv(value, Int32(dpi), 96)) }

        // 주 모니터 작업 영역 가운데에 클라이언트 340×132 (DIP)
        let exStyle = DWORD(truncatingIfNeeded: WS_EX_DLGMODALFRAME) | DWORD(truncatingIfNeeded: WS_EX_TOPMOST)
        let style = DWORD(truncatingIfNeeded: WS_POPUP) | DWORD(truncatingIfNeeded: WS_CAPTION) | DWORD(truncatingIfNeeded: WS_SYSMENU)
        var frame = RECT(left: 0, top: 0, right: scaled(340), bottom: scaled(132))
        _ = AdjustWindowRectExForDpi(&frame, style, false, exStyle, dpi)
        var work = RECT()
        _ = SystemParametersInfoW(UINT(SPI_GETWORKAREA), 0, &work, 0)
        let width = frame.right - frame.left, height = frame.bottom - frame.top
        let left = work.left + (work.right - work.left - width) / 2, top = work.top + (work.bottom - work.top - height) / 2
        guard let window = CreateWindowExW(exStyle, Self.windowClass.wide, title.wide, style, left, top, width, height,
                                           nil, nil, instance, nil) else { return nil }

        var metrics = NONCLIENTMETRICSW()
        metrics.cbSize = UINT(MemoryLayout<NONCLIENTMETRICSW>.size)
        _ = SystemParametersInfoForDpi(UINT(SPI_GETNONCLIENTMETRICS), metrics.cbSize, &metrics, 0, dpi)
        let font = CreateFontIndirectW(&metrics.lfMessageFont)

        func child(_ className: String, _ text: String, _ style: DWORD, _ x: Int32, _ y: Int32, _ w: Int32, _ h: Int32,
                   id: Int32, exStyle: DWORD = 0) -> HWND? {
            let visibleChild = DWORD(truncatingIfNeeded: WS_CHILD) | DWORD(truncatingIfNeeded: WS_VISIBLE)
            let made = CreateWindowExW(exStyle, className.wide, text.wide, visibleChild | style,
                                       scaled(x), scaled(y), scaled(w), scaled(h), window, HMENU(bitPattern: Int(id)), instance, nil)
            if let made, let font { _ = SendMessageW(made, UINT(WM_SETFONT), WPARAM(UInt(bitPattern: font)), 1) }
            return made
        }
        let tabStop = DWORD(truncatingIfNeeded: WS_TABSTOP)
        _ = child("STATIC", message, 0, 16, 14, 308, 34, id: 0)
        edit = child("EDIT", initial, tabStop | DWORD(truncatingIfNeeded: ES_AUTOHSCROLL), 16, 52, 308, 26, id: Self.editID,
                     exStyle: DWORD(truncatingIfNeeded: WS_EX_CLIENTEDGE))
        _ = child("BUTTON", save, tabStop | DWORD(truncatingIfNeeded: BS_DEFPUSHBUTTON), 148, 92, 84, 28, id: Self.saveID)
        _ = child("BUTTON", cancel, tabStop | DWORD(truncatingIfNeeded: BS_PUSHBUTTON), 240, 92, 84, 28, id: Self.cancelID)
        if let edit {
            _ = SendMessageW(edit, UINT(EM_LIMITTEXT), 64, 0)
            _ = SendMessageW(edit, UINT(EM_SETSEL), 0, -1)
        }

        _ = ShowWindow(window, SW_SHOW)
        _ = SetForegroundWindow(window)
        if let edit { _ = SetFocus(edit) }
        // 열린 동안에도 펫이 움직이게 (메뉴와 같은 타이머, WM_TIMER)
        _ = SetTimer(host, TrayMenu.menuTimerID, 16, nil)
        var pending = MSG()
        while !isFinished {
            guard GetMessageW(&pending, nil, 0, 0) else {
                // 앱이 끝나는 중: 바깥 메시지 루프도 끝나게 다시 알림
                PostQuitMessage(Int32(truncatingIfNeeded: pending.wParam))
                break
            }
            if !IsDialogMessageW(window, &pending) {
                _ = TranslateMessage(&pending)
                _ = DispatchMessageW(&pending)
            }
        }
        _ = KillTimer(host, TrayMenu.menuTimerID)
        _ = DestroyWindow(window)
        if let font { _ = DeleteObject(UnsafeMutableRawPointer(font)) }
        return typed
    }

    private static func text(of control: HWND) -> String {
        let length = Int(GetWindowTextLengthW(control))
        var buffer = [WCHAR](repeating: 0, count: length + 1)
        let copied = Int(GetWindowTextW(control, &buffer, Int32(buffer.count)))
        return String(wide: buffer, count: copied)
    }
}
