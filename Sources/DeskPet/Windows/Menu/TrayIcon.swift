import Foundation
import WinSDK

/// This object is responsible for turning a pet's standing picture into the small notification-area icon: it crops
/// the picture to the pet's drawn pixels, centers it in a square, scales it with nearest-neighbor sampling so the
/// pixel art stays sharp, and builds a 32-bit icon with straight alpha (the layout icons use).
enum TrayIcon {
    /// 펫 그림 → 트레이 아이콘. 못 만들면 nil (그때는 기본 앱 아이콘)
    static func make(from image: PremultipliedImage, mirrored: Bool = false) -> HICON? {
        let side = Int(GetSystemMetricsForDpi(SM_CXSMICON, GetDpiForSystem()))
        guard side > 0, let pixels = square(image, side: side, mirrored: mirrored) else { return nil }

        var info = BITMAPINFO()
        info.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        info.bmiHeader.biWidth = LONG(side)
        // 음수 높이: 위쪽 줄부터
        info.bmiHeader.biHeight = -LONG(side)
        info.bmiHeader.biPlanes = 1
        info.bmiHeader.biBitCount = 32
        info.bmiHeader.biCompression = DWORD(BI_RGB)
        var raw: UnsafeMutableRawPointer?
        guard let color = CreateDIBSection(nil, &info, UINT(DIB_RGB_COLORS), &raw, nil, 0), let raw else { return nil }
        pixels.withUnsafeBytes { raw.copyMemory(from: $0.baseAddress!, byteCount: pixels.count) }
        // 알파가 있는 32비트 아이콘은 마스크를 쓰지 않지만 자리는 있어야 함
        let maskBytes = [UInt8](repeating: 0, count: ((side + 15) / 16) * 2 * side)
        guard let mask = CreateBitmap(Int32(side), Int32(side), 1, 1, maskBytes) else {
            _ = DeleteObject(UnsafeMutableRawPointer(color))
            return nil
        }
        var icon = ICONINFO(fIcon: true, xHotspot: 0, yHotspot: 0, hbmMask: mask, hbmColor: color)
        let made = CreateIconIndirect(&icon)
        _ = DeleteObject(UnsafeMutableRawPointer(color))
        _ = DeleteObject(UnsafeMutableRawPointer(mask))
        return made
    }

    /// 그린 픽셀만 잘라 정사각형 가운데에 두고 side로 늘린 곧은 알파 BGRA
    private static func square(_ image: PremultipliedImage, side: Int, mirrored: Bool) -> [UInt8]? {
        var left = image.width, top = image.height, right = -1, bottom = -1
        for y in 0..<image.height {
            for x in 0..<image.width where image.bgra[(y * image.width + x) * 4 + 3] > 0 {
                left = min(left, x); right = max(right, x)
                top = min(top, y); bottom = max(bottom, y)
            }
        }
        guard right >= left, bottom >= top else { return nil }
        let span = max(right - left, bottom - top) + 1
        let originX = left - (span - (right - left + 1)) / 2
        // 발이 아이콘 바닥에 닿게 아래를 맞춤
        let originY = bottom + 1 - span
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for row in 0..<side {
            for column in 0..<side {
                var x = originX + (column * 2 + 1) * span / (side * 2)
                let y = originY + (row * 2 + 1) * span / (side * 2)
                if mirrored { x = originX + span - 1 - (x - originX) }
                guard x >= 0, x < image.width, y >= 0, y < image.height else { continue }
                let source = (y * image.width + x) * 4, target = (row * side + column) * 4
                let alpha = Int(image.bgra[source + 3])
                guard alpha > 0 else { continue }
                // 미리 곱한 값 → 곧은 알파
                for channel in 0..<3 {
                    pixels[target + channel] = UInt8(min(Int(image.bgra[source + channel]) * 255 / alpha, 255))
                }
                pixels[target + 3] = UInt8(alpha)
            }
        }
        return pixels
    }
}
