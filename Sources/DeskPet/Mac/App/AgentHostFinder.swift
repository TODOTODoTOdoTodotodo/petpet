import AppKit

/// This object is responsible for finding the app an AI tool's session lives in — walking up from the tool's process
/// through its parents to the first app with windows (Claude, Terminal, VS Code …) — and for turning that app's icon
/// into a small dot badge for speech bubbles. It looks only at the process tree, never at what the processes do.
final class AgentHostFinder {
    /// 아이콘 한 변 픽셀 수 (말풍선에서 1.5배로 그림)
    static let iconSide = 12
    /// 부모를 따라 올라가는 최대 단계
    static let maxDepth = 32

    private var badges: [String: SpeechBadge] = [:]

    /// withDockIcon: Dock 아이콘 자리도 찾음 (Dock 아이콘 찾아가기를 켰을 때)
    func host(for processID: Int32?, withDockIcon: Bool = false) -> AgentHost? {
        guard let processID, let app = Self.windowedApp(above: processID) else { return nil }
        return AgentHost(processID: app.processIdentifier, badge: badge(for: app),
                         dockIcon: withDockIcon ? DockIconLocator.iconFrame(of: app) : nil)
    }

    /// 그 프로세스나 조상 중 처음 만나는, 독에 보이는 앱 (DeskPet 자신은 제외)
    static func windowedApp(above processID: Int32) -> NSRunningApplication? {
        var current = processID
        for _ in 0..<maxDepth {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular,
               app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                return app
            }
            guard let parent = parentID(of: current), parent > 1, parent != current else { return nil }
            current = parent
        }
        return nil
    }

    private static func parentID(of processID: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, processID]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    private func badge(for app: NSRunningApplication) -> SpeechBadge? {
        let id = app.bundleIdentifier ?? app.executableURL?.path ?? "\(app.processIdentifier)"
        if let cached = badges[id] { return cached }
        guard let icon = app.icon, let pixels = Self.dots(from: icon, side: Self.iconSide) else { return nil }
        let badge = SpeechBadge(id: id, pixels: pixels)
        badges[id] = badge
        return badge
    }

    /// 아이콘의 투명 여백을 잘라 side×side로 줄이고, 알파를 0·255로 나눠 도트처럼 만듦
    static func dots(from image: NSImage, side: Int) -> SpritePixels? {
        let large = 128
        guard let full = render(image, side: large), let bounds = opaqueBounds(full, side: large) else { return nil }
        let length = max(bounds.width, bounds.height)
        let square = CGRect(x: bounds.midX - length / 2, y: bounds.midY - length / 2, width: length, height: length)
        guard let cropped = full.cgImage?.cropping(to: square.integral) else { return nil }
        let small = NSImage(cgImage: cropped, size: NSSize(width: side, height: side))
        guard let bitmap = render(small, side: side) else { return nil }
        var rgba = [UInt8](repeating: 0, count: side * side * 4)
        for row in 0..<side {
            for column in 0..<side {
                guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.sRGB), color.alphaComponent >= 0.5 else { continue }
                let index = (row * side + column) * 4
                rgba[index] = UInt8((color.redComponent * 255).rounded())
                rgba[index + 1] = UInt8((color.greenComponent * 255).rounded())
                rgba[index + 2] = UInt8((color.blueComponent * 255).rounded())
                rgba[index + 3] = 255
            }
        }
        return SpritePixels(width: side, height: side, rgba: rgba)
    }

    private static func render(_ image: NSImage, side: Int) -> NSBitmapImageRep? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    /// 불투명한 픽셀이 차지하는 사각형 (비트맵 좌표, 맨 윗줄이 0)
    private static func opaqueBounds(_ bitmap: NSBitmapImageRep, side: Int) -> CGRect? {
        var (minX, minY, maxX, maxY) = (side, side, -1, -1)
        for row in 0..<side {
            for column in 0..<side where (bitmap.colorAt(x: column, y: row)?.alphaComponent ?? 0) > 0.1 {
                (minX, minY, maxX, maxY) = (min(minX, column), min(minY, row), max(maxX, column), max(maxY, row))
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
