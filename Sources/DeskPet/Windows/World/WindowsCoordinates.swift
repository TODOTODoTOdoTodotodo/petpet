import Foundation
import WinSDK

/// This object is responsible for converting between Windows virtual-screen pixels
/// (origin at the primary monitor's top-left, +y down) and the shared global coordinates
/// (origin at the primary monitor's bottom-left, +y up), the same flip macOS does from Quartz to Cocoa.
/// One shared unit is one primary-monitor "point": pixels ÷ the primary monitor's scale (DPI / 96),
/// so pets keep the size the user's display scaling asks for, like points on macOS.
struct WindowsCoordinates {
    /// 주 모니터 높이 (픽셀)
    let primaryHeight: CGFloat
    /// 공통 좌표 1단위의 픽셀 수 (주 모니터 배율)
    let unit: CGFloat

    init(primaryHeight: CGFloat, unit: CGFloat = 1) {
        self.primaryHeight = primaryHeight
        self.unit = max(unit, 0.5)
    }

    /// 지금 주 모니터 기준 (모니터 구성이 바뀌어도 매번 새로 읽음)
    static func current() -> WindowsCoordinates {
        var info = MONITORINFO()
        info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        guard let primary = MonitorFromPoint(POINT(x: 0, y: 0), DWORD(MONITOR_DEFAULTTOPRIMARY)),
              GetMonitorInfoW(primary, &info) else {
            return WindowsCoordinates(primaryHeight: 0)
        }
        var dpiX: UINT = 96
        var dpiY: UINT = 96
        _ = GetDpiForMonitor(primary, MDT_EFFECTIVE_DPI, &dpiX, &dpiY)
        return WindowsCoordinates(primaryHeight: CGFloat(info.rcMonitor.bottom - info.rcMonitor.top), unit: CGFloat(dpiX) / 96)
    }

    func rect(_ rect: RECT) -> CGRect {
        CGRect(x: CGFloat(rect.left) / unit, y: (primaryHeight - CGFloat(rect.bottom)) / unit,
               width: CGFloat(rect.right - rect.left) / unit, height: CGFloat(rect.bottom - rect.top) / unit)
    }

    func point(_ point: POINT) -> CGPoint {
        CGPoint(x: CGFloat(point.x) / unit, y: (primaryHeight - CGFloat(point.y)) / unit)
    }

    func screenPoint(_ point: CGPoint) -> POINT {
        POINT(x: LONG((point.x * unit).rounded()), y: LONG((primaryHeight - point.y * unit).rounded()))
    }

    /// 공통 좌표 사각형 → 한 모니터 안의 픽셀 사각형 (origin: 그 모니터 왼쪽 위의 가상 화면 픽셀)
    func pixelBox(_ rect: CGRect, origin: POINT) -> PixelBox {
        let left = (rect.minX * unit).rounded() - CGFloat(origin.x)
        let top = (primaryHeight - rect.maxY * unit).rounded() - CGFloat(origin.y)
        return PixelBox(x: Int(left), y: Int(top), width: Int((rect.width * unit).rounded()), height: Int((rect.height * unit).rounded()))
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
