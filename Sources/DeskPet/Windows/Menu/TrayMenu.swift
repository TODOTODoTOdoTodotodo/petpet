import Foundation
import WinSDK

/// This object is responsible for DeskPet's notification-area (tray) icon and for showing the shared menu data
/// (`MenuNode`) as Win32 popup menus: it numbers each command row, remembers which submenu reports what when it
/// opens, and maps the chosen menu ID back to its `MenuCommand`.
final class TrayMenu {
    /// 트레이 아이콘이 창에 보내는 메시지
    static let callbackMessage = UINT(WM_APP) + 1
    private static let iconID: UINT = 1

    private let window: HWND
    private var commands: [UINT: MenuCommand] = [:]
    private var openNotices: [UInt: MenuCommand] = [:]
    private var nextID: UINT = 0
    private(set) var isShown = false

    init(window: HWND) {
        self.window = window
    }

    /// 트레이에 아이콘을 올림 (탐색기가 다시 시작돼도 다시 부름)
    @discardableResult
    func show(tip: String) -> Bool {
        var data = baseData()
        data.uFlags = UINT(NIF_ICON | NIF_MESSAGE | NIF_TIP)
        data.uCallbackMessage = Self.callbackMessage
        // 기본 앱 아이콘 (IDI_APPLICATION). 펫 아이콘은 포장 단계에서
        data.hIcon = LoadIconW(nil, UnsafePointer<WCHAR>(bitPattern: 32512))
        let units = Array(tip.utf16.prefix(127)) + [0]
        withUnsafeMutableBytes(of: &data.szTip) { target in
            units.withUnsafeBytes { source in target.copyMemory(from: source) }
        }
        isShown = Shell_NotifyIconW(DWORD(NIM_ADD), &data)
        return isShown
    }

    func remove() {
        guard isShown else { return }
        var data = baseData()
        _ = Shell_NotifyIconW(DWORD(NIM_DELETE), &data)
        isShown = false
    }

    private func baseData() -> NOTIFYICONDATAW {
        var data = NOTIFYICONDATAW()
        data.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
        data.hWnd = window
        data.uID = Self.iconID
        return data
    }

    // MARK: - Popup menus

    /// 포인터 자리에 메뉴를 띄움. 고른 항목은 WM_COMMAND로 창에 옴
    func popUp(_ nodes: [MenuNode]) {
        commands = [:]
        openNotices = [:]
        nextID = 0
        guard let menu = build(nodes) else { return }
        var point = POINT()
        _ = GetCursorPos(&point)
        // 창을 앞으로 가져와야 메뉴 밖을 눌렀을 때 메뉴가 닫힘
        _ = SetForegroundWindow(window)
        _ = TrackPopupMenu(menu, UINT(TPM_RIGHTBUTTON), point.x, point.y, 0, window, nil)
        _ = PostMessageW(window, UINT(WM_NULL), 0, 0)
        _ = DestroyMenu(menu)
    }

    /// WM_COMMAND의 메뉴 ID → 고른 일
    func command(for id: UINT) -> MenuCommand? {
        commands[id]
    }

    /// WM_INITMENUPOPUP으로 열린 하위 메뉴 → 열 때 알릴 일
    func openNotice(for menu: WPARAM) -> MenuCommand? {
        openNotices[UInt(menu)]
    }

    private func build(_ nodes: [MenuNode]) -> HMENU? {
        guard let menu = CreatePopupMenu() else { return nil }
        for node in nodes {
            switch node.kind {
            case .separator:
                _ = AppendMenuW(menu, UINT(MF_SEPARATOR), 0, nil)
            case .heading:
                _ = AppendMenuW(menu, UINT(MF_STRING) | UINT(MF_GRAYED), 0, node.title.wide)
            case .info:
                // 보기만 하는 줄: ID 0은 고르면 아무 일 없음
                _ = AppendMenuW(menu, UINT(MF_STRING), 0, node.title.wide)
            case .command(let command):
                nextID += 1
                commands[nextID] = command
                var flags = UINT(MF_STRING)
                if node.checked { flags |= UINT(MF_CHECKED) }
                if !node.enabled { flags |= UINT(MF_GRAYED) }
                _ = AppendMenuW(menu, flags, UINT_PTR(nextID), node.title.wide)
            case .submenu(let children, let onOpen):
                guard let child = build(children) else { continue }
                let handle = UInt(bitPattern: child)
                if let onOpen { openNotices[handle] = onOpen }
                _ = AppendMenuW(menu, UINT(MF_POPUP), UINT_PTR(handle), node.title.wide)
            }
        }
        return menu
    }
}

/// This object is responsible for the confirm dialogs a menu choice needs on Windows (message boxes).
/// Text entry (naming a pet) needs a custom dialog and arrives in phase 3; until then naming is skipped.
final class WindowsMenuDialogs: MenuDialogs {
    func confirm(title: String, message: String, confirm: String, cancel: String) -> Bool {
        MessageBoxW(nil, message.wide, title.wide, UINT(MB_OKCANCEL) | UINT(MB_ICONWARNING) | UINT(MB_TOPMOST)) == IDOK
    }

    func askText(title: String, message: String, initial: String, save: String, cancel: String) -> String? {
        WindowsLogger.shared.log("🏷️ naming needs a text dialog (phase 3), skipped")
        return nil
    }
}
