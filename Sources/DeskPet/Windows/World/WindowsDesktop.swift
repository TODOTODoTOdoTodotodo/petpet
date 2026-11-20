import Foundation
import WinSDK

/// This object is responsible for reading monitors (work areas without the taskbar), visible app windows
/// front to back, and the foreground app from Windows, in the shared global coordinates.
/// Window edges come from DWM's extended frame bounds, because `GetWindowRect` includes an invisible
/// resize border that would leave pets standing in the air.
final class WindowsDesktop: DesktopSource {
    private let ownPID = GetCurrentProcessId()
    /// 발판으로 쓰지 않을 창 종류 (바탕 화면, 작업 표시줄, DeskPet 자신)
    private static let ignoredClasses: Set<String> = [
        "Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd", WindowsApp.windowClass,
    ]
    /// 이보다 작은 창은 제외
    private let minimumWindowSide: CGFloat = 100
    /// 프로세스 ID → 실행 파일 이름
    private var exeNames: [DWORD: String] = [:]

    func displays() -> [ScreenArea] {
        let coordinates = WindowsCoordinates.current()
        let collector = Win32Collector<HMONITOR>()
        withExtendedLifetime(collector) {
            _ = EnumDisplayMonitors(nil, nil, { (monitor, _, _, context) -> WindowsBool in
                if let monitor { Win32Collector<HMONITOR>.from(context).items.append(monitor) }
                return true
            }, collector.context)
        }
        return collector.items.enumerated().compactMap { index, monitor in
            var info = MONITORINFO()
            info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
            guard GetMonitorInfoW(monitor, &info) else { return nil }
            var dpiX: UINT = 96
            var dpiY: UINT = 96
            _ = GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &dpiX, &dpiY)
            let primary = info.dwFlags & DWORD(MONITORINFOF_PRIMARY) != 0
            return ScreenArea(
                id: UInt32(truncatingIfNeeded: UInt(bitPattern: monitor)),
                name: "Display \(index + 1)" + (primary ? " (primary)" : ""),
                frame: coordinates.rect(info.rcMonitor),
                visibleFrame: coordinates.rect(info.rcWork),
                backingScale: CGFloat(dpiX) / 96
            )
        }
    }

    func windows() -> [WindowSnapshot] {
        let coordinates = WindowsCoordinates.current()
        let collector = Win32Collector<HWND>()
        // EnumWindows는 위(앞)에서 아래(뒤) 순서
        withExtendedLifetime(collector) {
            _ = EnumWindows({ (window, context) -> WindowsBool in
                if let window { Win32Collector<HWND>.from(context).items.append(window) }
                return true
            }, collector.context)
        }
        return collector.items.compactMap { snapshot(of: $0, coordinates) }
    }

    func frontmostApp() -> FrontApp? {
        guard let window = GetForegroundWindow() else { return nil }
        var pid: DWORD = 0
        _ = GetWindowThreadProcessId(window, &pid)
        guard pid != 0 else { return nil }
        return FrontApp(processID: Int32(bitPattern: pid), bundleID: exeName(of: pid))
    }

    // MARK: - Windows

    private func snapshot(of window: HWND, _ coordinates: WindowsCoordinates) -> WindowSnapshot? {
        guard IsWindowVisible(window), !IsIconic(window) else { return nil }
        // 도구 창(떠 있는 팔레트 등)은 제외
        guard GetWindowLongPtrW(window, GWL_EXSTYLE) & LONG_PTR(WS_EX_TOOLWINDOW) == 0 else { return nil }
        // 다른 가상 데스크톱에 있거나 숨겨 둔 창(UWP 대기 창)은 보이지 않음
        var cloaked: DWORD = 0
        if DwmGetWindowAttribute(window, DWORD(DWMWA_CLOAKED.rawValue), &cloaked, DWORD(MemoryLayout<DWORD>.size)) >= 0,
           cloaked != 0 {
            return nil
        }
        guard !Self.ignoredClasses.contains(className(of: window)) else { return nil }

        var bounds = RECT()
        if DwmGetWindowAttribute(window, DWORD(DWMWA_EXTENDED_FRAME_BOUNDS.rawValue), &bounds, DWORD(MemoryLayout<RECT>.size)) < 0 {
            guard GetWindowRect(window, &bounds) else { return nil }
        }
        let frame = coordinates.rect(bounds)
        guard frame.width >= minimumWindowSide, frame.height >= minimumWindowSide else { return nil }

        var pid: DWORD = 0
        _ = GetWindowThreadProcessId(window, &pid)
        guard pid != ownPID else { return nil }
        return WindowSnapshot(id: UInt32(truncatingIfNeeded: UInt(bitPattern: window)), owner: exeName(of: pid),
                              frame: frame, processID: Int32(bitPattern: pid))
    }

    private func className(of window: HWND) -> String {
        var buffer = [WCHAR](repeating: 0, count: 256)
        let length = GetClassNameW(window, &buffer, Int32(buffer.count))
        return String(wide: buffer, count: Int(max(length, 0)))
    }

    /// 실행 파일 이름 (예: notepad.exe). 읽지 못하면 "pid 123"
    private func exeName(of pid: DWORD) -> String {
        if let cached = exeNames[pid] { return cached }
        var name = "pid \(pid)"
        if let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, pid) {
            defer { _ = CloseHandle(process) }
            var buffer = [WCHAR](repeating: 0, count: 1024)
            var size = DWORD(buffer.count)
            if QueryFullProcessImageNameW(process, 0, &buffer, &size) {
                let path = String(wide: buffer, count: Int(size))
                name = path.split(separator: "\\").last.map(String.init) ?? path
            }
        }
        exeNames[pid] = name
        return name
    }
}
