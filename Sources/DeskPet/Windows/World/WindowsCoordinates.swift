import Foundation
import WinSDK

/// This object is responsible for converting between Windows virtual-screen pixels
/// (origin at the primary monitor's top-left, +y down) and the shared global coordinates
/// (origin at the primary monitor's bottom-left, +y up), the same flip macOS does from Quartz to Cocoa.
struct WindowsCoordinates {
    /// 주 모니터 높이 (픽셀)
    let primaryHeight: CGFloat

    /// 지금 주 모니터 기준 (모니터 구성이 바뀌어도 매번 새로 읽음)
    static func current() -> WindowsCoordinates {
        var info = MONITORINFO()
        info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        guard let primary = MonitorFromPoint(POINT(x: 0, y: 0), DWORD(MONITOR_DEFAULTTOPRIMARY)),
              GetMonitorInfoW(primary, &info) else {
            return WindowsCoordinates(primaryHeight: 0)
        }
        return WindowsCoordinates(primaryHeight: CGFloat(info.rcMonitor.bottom - info.rcMonitor.top))
    }

    func rect(_ rect: RECT) -> CGRect {
        CGRect(x: CGFloat(rect.left), y: primaryHeight - CGFloat(rect.bottom),
               width: CGFloat(rect.right - rect.left), height: CGFloat(rect.bottom - rect.top))
    }

    func point(_ point: POINT) -> CGPoint {
        CGPoint(x: CGFloat(point.x), y: primaryHeight - CGFloat(point.y))
    }

    func screenPoint(_ point: CGPoint) -> POINT {
        POINT(x: LONG(point.x.rounded()), y: LONG((primaryHeight - point.y).rounded()))
    }
}

/// This object is responsible for collecting what a Win32 enumeration callback reports,
/// passed through the callback's `LPARAM` because C callbacks cannot capture Swift context.
final class Win32Collector<Item> {
    var items: [Item] = []

    var context: LPARAM {
        LPARAM(Int(bitPattern: Unmanaged.passUnretained(self).toOpaque()))
    }

    static func from(_ context: LPARAM) -> Win32Collector<Item> {
        Unmanaged<Win32Collector<Item>>.fromOpaque(UnsafeRawPointer(bitPattern: Int(context))!).takeUnretainedValue()
    }
}

extension String {
    /// 널로 끝나는 UTF-16 (Win32 W 함수용)
    var wide: [WCHAR] { Array(utf16) + [0] }

    /// 널로 끝나는 UTF-16 버퍼에서 읽음
    init(wide buffer: [WCHAR], count: Int? = nil) {
        let units = buffer.prefix(count ?? buffer.firstIndex(of: 0) ?? buffer.count)
        self = String(decoding: units, as: UTF16.self)
    }
}
