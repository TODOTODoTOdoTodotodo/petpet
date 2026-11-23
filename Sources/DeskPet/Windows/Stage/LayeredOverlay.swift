import Foundation
import WinSDK

/// 한 오버레이에 그릴 그림 하나 (그 모니터 안의 픽셀 좌표)
struct OverlaySprite {
    let image: PremultipliedImage
    let box: PixelBox
    var mirrored = false
    var flipped = false
    var visibleShare: CGFloat = 1
    var alpha: CGFloat = 1
}

/// This object is responsible for one monitor's transparent, always-on-top window (`WS_EX_LAYERED`):
/// it keeps a premultiplied BGRA canvas, redraws only where sprites were and are, uploads just that changed
/// region with `UpdateLayeredWindowIndirect`, and lets clicks through (`WS_EX_TRANSPARENT`) unless the
/// pointer is over something a pet owner can grab; its mouse messages go to `onMouse`.
final class LayeredOverlay {
    static let windowClass = "DeskPetOverlay"
    private static var isRegistered = false
    /// 오버레이가 받은 마우스 메시지 (처리하면 결과를 돌려줌). C 창 프로시저는 문맥을 잡을 수 없어 정적 자리에 둠
    static var onMouse: ((HWND, UINT) -> LRESULT?)?

    /// 이 모니터 왼쪽 위의 가상 화면 픽셀 좌표
    let origin: POINT
    let canvas: PixelCanvas
    private let window: HWND
    private let memoryDC: HDC
    private let bitmap: HBITMAP
    private let bits: UnsafeMutableRawPointer
    /// 지난번에 그린 자리 (이번에 지울 곳)
    private var drawn: [PixelBox] = []
    private var exStyle: DWORD
    /// 클릭을 받는지 (끄면 모든 클릭이 뒤 창으로 감)
    var catchesMouse = false {
        didSet {
            guard catchesMouse != oldValue else { return }
            let transparent = DWORD(truncatingIfNeeded: WS_EX_TRANSPARENT)
            exStyle = catchesMouse ? exStyle & ~transparent : exStyle | transparent
            _ = SetWindowLongPtrW(window, GWL_EXSTYLE, LONG_PTR(exStyle))
        }
    }

    /// box: 모니터의 가상 화면 픽셀 사각형
    init?(box: PixelBox, instance: HINSTANCE?) {
        guard box.width > 0, box.height > 0, Self.register(instance) else { return nil }
        origin = POINT(x: LONG(box.x), y: LONG(box.y))
        canvas = PixelCanvas(width: box.width, height: box.height)

        // 처음에는 클릭 관통. 펫 위에 포인터가 오면 catchesMouse로 끔
        let exStyle = DWORD(truncatingIfNeeded: WS_EX_LAYERED) | DWORD(truncatingIfNeeded: WS_EX_TOOLWINDOW)
            | DWORD(truncatingIfNeeded: WS_EX_TOPMOST) | DWORD(truncatingIfNeeded: WS_EX_NOACTIVATE)
            | DWORD(truncatingIfNeeded: WS_EX_TRANSPARENT)
        guard let window = CreateWindowExW(exStyle, Self.windowClass.wide, "DeskPet".wide, DWORD(truncatingIfNeeded: WS_POPUP),
                                           origin.x, origin.y, Int32(box.width), Int32(box.height), nil, nil, instance, nil) else {
            return nil
        }

        var info = BITMAPINFO()
        info.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        info.bmiHeader.biWidth = LONG(box.width)
        // 음수 높이: 위쪽 줄부터 (캔버스와 같은 배치)
        info.bmiHeader.biHeight = -LONG(box.height)
        info.bmiHeader.biPlanes = 1
        info.bmiHeader.biBitCount = 32
        info.bmiHeader.biCompression = DWORD(BI_RGB)
        var raw: UnsafeMutableRawPointer?
        guard let memoryDC = CreateCompatibleDC(nil),
              let bitmap = CreateDIBSection(memoryDC, &info, UINT(DIB_RGB_COLORS), &raw, nil, 0),
              let raw else {
            _ = DestroyWindow(window)
            return nil
        }
        _ = SelectObject(memoryDC, UnsafeMutableRawPointer(bitmap))
        self.exStyle = exStyle
        self.window = window
        self.memoryDC = memoryDC
        self.bitmap = bitmap
        bits = raw

        // 처음에는 전체를 투명하게 올려 창 크기를 정함
        canvas.clear(canvas.bounds)
        upload()
        _ = ShowWindow(window, SW_SHOWNOACTIVATE)
    }

    private static func register(_ instance: HINSTANCE?) -> Bool {
        guard !isRegistered else { return true }
        let name = windowClass.wide
        let atom = name.withUnsafeBufferPointer { pointer -> ATOM in
            var windowClass = WNDCLASSEXW()
            windowClass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
            windowClass.lpfnWndProc = { window, message, wParam, lParam in
                if let window, let result = LayeredOverlay.onMouse?(window, message) { return result }
                return DefWindowProcW(window, message, wParam, lParam)
            }
            windowClass.hInstance = instance
            // 기본 화살표 (IDC_ARROW). 없으면 펫 위에서 커서가 그 전 모양으로 남음
            windowClass.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512))
            windowClass.lpszClassName = pointer.baseAddress
            return RegisterClassExW(&windowClass)
        }
        isRegistered = atom != 0
        return isRegistered
    }

    /// 지난 그림을 지우고 새로 그린 뒤, 바뀐 곳만 화면에 올림. hitAreas: 빈 픽셀도 클릭을 받을 자리 (펫 잡기 영역)
    func render(_ sprites: [OverlaySprite], hitAreas: [PixelBox] = []) {
        drawn.forEach(canvas.clear)
        drawn = sprites.map {
            canvas.draw($0.image, in: $0.box, mirrored: $0.mirrored, flipped: $0.flipped, visibleShare: $0.visibleShare, alpha: $0.alpha)
        } + hitAreas.map(canvas.markHitArea)
        drawn.removeAll(where: \.isEmpty)
        upload()
    }

    private func upload() {
        let dirty = canvas.takeDirty()
        guard !dirty.isEmpty else { return }
        // 바뀐 줄만 DIB로 복사
        canvas.bgra.withUnsafeBytes { source in
            for row in dirty.y..<dirty.maxY {
                let offset = (row * canvas.width + dirty.x) * 4
                (bits + offset).copyMemory(from: source.baseAddress! + offset, byteCount: dirty.width * 4)
            }
        }
        var destination = origin
        var size = SIZE(cx: LONG(canvas.width), cy: LONG(canvas.height))
        var source = POINT(x: 0, y: 0)
        var blend = BLENDFUNCTION()
        blend.BlendOp = BYTE(AC_SRC_OVER)
        blend.SourceConstantAlpha = 255
        blend.AlphaFormat = BYTE(AC_SRC_ALPHA)
        var changed = RECT(left: LONG(dirty.x), top: LONG(dirty.y), right: LONG(dirty.maxX), bottom: LONG(dirty.maxY))
        withUnsafePointer(to: &destination) { destinationPointer in
            withUnsafePointer(to: &size) { sizePointer in
                withUnsafePointer(to: &source) { sourcePointer in
                    withUnsafePointer(to: &blend) { blendPointer in
                        withUnsafePointer(to: &changed) { changedPointer in
                            var info = UPDATELAYEREDWINDOWINFO()
                            info.cbSize = DWORD(MemoryLayout<UPDATELAYEREDWINDOWINFO>.size)
                            info.pptDst = destinationPointer
                            info.psize = sizePointer
                            info.hdcSrc = memoryDC
                            info.pptSrc = sourcePointer
                            info.pblend = blendPointer
                            info.dwFlags = DWORD(ULW_ALPHA)
                            info.prcDirty = changedPointer
                            _ = UpdateLayeredWindowIndirect(window, &info)
                        }
                    }
                }
            }
        }
    }

    func close() {
        _ = DestroyWindow(window)
        _ = DeleteDC(memoryDC)
        _ = DeleteObject(UnsafeMutableRawPointer(bitmap))
    }
}
