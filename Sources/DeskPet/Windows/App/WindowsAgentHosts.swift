import Foundation
import WinSDK

/// This object is responsible for the Windows side of AI task alerts: finding the app an AI tool's session lives in —
/// walking up from the process the hook named through its parents (toolhelp snapshot) to the first process that owns a
/// visible top-level window (Windows Terminal, VS Code, a console window …) — turning that app's icon into a 12×12 dot
/// badge for speech bubbles, and bringing the app's window forward when the user pokes the pet holding its bubble.
/// It looks only at the process tree and window list, never at what the processes do.
final class WindowsAgentHosts {
    /// 아이콘 한 변 도트 수 (말풍선에서 1.5배로 그림, 맥과 같음)
    static let iconSide = 12
    /// 아이콘을 그려 볼 크기 (큰 아이콘 기본 크기)
    static let renderSide = 32
    /// 부모를 따라 올라가는 최대 단계
    static let maxDepth = 32
    /// 여기까지 올라오면 창 있는 앱을 못 찾은 것으로 봄 (탐색기 창을 세션의 앱으로 잘못 고르지 않게)
    static let shellNames: Set<String> = ["explorer.exe", "svchost.exe", "services.exe", "wininit.exe", "winlogon.exe"]

    private var badges: [String: SpeechBadge] = [:]
    /// 마지막으로 찾은 결과 (연기 시험 보고서용)
    private(set) var lastLookup: [String: Any] = [:]

    /// 그 프로세스나 조상 중 처음 만나는, 창이 보이는 앱 (DeskPet 자신은 제외). 못 찾으면 nil
    func host(for processID: Int32?) -> AgentHost? {
        guard let processID, processID > 0 else { return nil }
        lastLookup = ["requested": Int(processID)]
        let tree = Self.processTree()
        let windowed = Self.topWindows()
        let own = GetCurrentProcessId()
        var current = DWORD(bitPattern: processID)
        var visited = Set<DWORD>()
        for depth in 0..<Self.maxDepth {
            guard let entry = tree[current], visited.insert(current).inserted else { break }
            if Self.shellNames.contains(entry.name.lowercased()) { break }
            if current != own, let window = windowed[current] {
                let badge = badge(for: current, name: entry.name, window: window)
                lastLookup.merge(["host": entry.name, "hostPID": Int(current), "depth": depth, "badge": badge?.id ?? ""]) { $1 }
                return AgentHost(processID: Int32(bitPattern: current), badge: badge)
            }
            current = entry.parent
            if current == 0 { break }
        }
        lastLookup["host"] = ""
        return nil
    }

    /// 그 앱의 맨 앞 창을 앞으로 (최소화돼 있으면 되살림). 펫을 누른 직후라 이 프로세스가 마지막 입력을 받아 허용됨
    @discardableResult
    func bringForward(_ processID: Int32) -> Bool {
        guard let window = Self.topWindows()[DWORD(bitPattern: processID)] else { return false }
        if IsIconic(window) { _ = ShowWindow(window, SW_RESTORE) }
        return SetForegroundWindow(window)
    }

    // MARK: - Processes and windows

    /// 프로세스 ID → (부모 ID, 실행 파일 이름)
    private static func processTree() -> [DWORD: (parent: DWORD, name: String)] {
        guard let snapshot = CreateToolhelp32Snapshot(DWORD(TH32CS_SNAPPROCESS), 0), snapshot != HANDLE(bitPattern: -1) else { return [:] }
        defer { _ = CloseHandle(snapshot) }
        var entry = PROCESSENTRY32W()
        entry.dwSize = DWORD(MemoryLayout<PROCESSENTRY32W>.size)
        var tree: [DWORD: (parent: DWORD, name: String)] = [:]
        guard Process32FirstW(snapshot, &entry) else { return [:] }
        repeat {
            let name = withUnsafeBytes(of: entry.szExeFile) { raw in
                String(decoding: raw.bindMemory(to: UInt16.self).prefix { $0 != 0 }, as: UTF16.self)
            }
            tree[entry.th32ProcessID] = (entry.th32ParentProcessID, name)
        } while Process32NextW(snapshot, &entry)
        return tree
    }

    /// 프로세스 ID → 그 프로세스의 맨 앞 창. 보이고, 제목이 있고, 소유 창·도구 창·숨김(cloaked) 창이 아닌 최상위 창만.
    /// 콘솔 창은 윈도우가 그 콘솔을 띄운 프로세스(cmd, pwsh …)의 창으로 알려 줌
    static func topWindows() -> [DWORD: HWND] {
        let collector = Win32Collector<HWND>()
        withExtendedLifetime(collector) {
            _ = EnumWindows({ (window, context) -> WindowsBool in
                if let window { Win32Collector<HWND>.from(context).items.append(window) }
                return true
            }, collector.context)
        }
        var found: [DWORD: HWND] = [:]
        for window in collector.items where IsWindowVisible(window) && GetWindow(window, UINT(GW_OWNER)) == nil
            && GetWindowTextLengthW(window) > 0
            && GetWindowLongPtrW(window, GWL_EXSTYLE) & LONG_PTR(WS_EX_TOOLWINDOW) == 0 {
            var cloaked: DWORD = 0
            if DwmGetWindowAttribute(window, DWORD(DWMWA_CLOAKED.rawValue), &cloaked, DWORD(MemoryLayout<DWORD>.size)) >= 0,
               cloaked != 0 { continue }
            var pid: DWORD = 0
            _ = GetWindowThreadProcessId(window, &pid)
            // EnumWindows는 앞에서 뒤 순서라 처음 만난 창이 맨 앞
            if pid != 0, found[pid] == nil { found[pid] = window }
        }
        return found
    }

    // MARK: - Badge

    private func badge(for processID: DWORD, name: String, window: HWND) -> SpeechBadge? {
        let id = Self.imagePath(of: processID) ?? name
        if let cached = badges[id] { return cached }
        guard let pixels = Self.iconPixels(window: window, path: Self.imagePath(of: processID)).flatMap(Self.dots) else { return nil }
        let badge = SpeechBadge(id: id, pixels: pixels)
        badges[id] = badge
        return badge
    }

    private static func imagePath(of processID: DWORD) -> String? {
        guard let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, processID) else { return nil }
        defer { _ = CloseHandle(process) }
        var buffer = [WCHAR](repeating: 0, count: 1024)
        var size = DWORD(buffer.count)
        guard QueryFullProcessImageNameW(process, 0, &buffer, &size) else { return nil }
        return String(wide: buffer, count: Int(size))
    }

    /// 창 아이콘(작업 표시줄에 보이는 것) → 없으면 실행 파일 아이콘을 renderSide로 그린 미리 곱한 BGRA (위쪽 줄부터)
    private static func iconPixels(window: HWND, path: String?) -> [UInt8]? {
        var result: DWORD_PTR = 0
        if SendMessageTimeoutW(window, UINT(WM_GETICON), WPARAM(ICON_BIG), 0, UINT(SMTO_ABORTIFHUNG), 200, &result) != 0, result != 0,
           let icon = HICON(bitPattern: UInt(result)), let pixels = render(icon) {
            return pixels
        }
        let classIcon = GetClassLongPtrW(window, GCLP_HICON)
        if classIcon != 0, let icon = HICON(bitPattern: UInt(classIcon)), let pixels = render(icon) {
            return pixels
        }
        guard let path else { return nil }
        var large: HICON?
        guard ExtractIconExW(path.wide, 0, &large, nil, 1) > 0, let large else { return nil }
        defer { _ = DestroyIcon(large) }
        return render(large)
    }

    private static func render(_ icon: HICON) -> [UInt8]? {
        let side = renderSide
        var info = BITMAPINFO()
        info.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        info.bmiHeader.biWidth = LONG(side)
        info.bmiHeader.biHeight = -LONG(side)
        info.bmiHeader.biPlanes = 1
        info.bmiHeader.biBitCount = 32
        info.bmiHeader.biCompression = DWORD(BI_RGB)
        var raw: UnsafeMutableRawPointer?
        guard let context = CreateCompatibleDC(nil) else { return nil }
        defer { _ = DeleteDC(context) }
        guard let bitmap = CreateDIBSection(context, &info, UINT(DIB_RGB_COLORS), &raw, nil, 0), let raw else { return nil }
        defer { _ = DeleteObject(UnsafeMutableRawPointer(bitmap)) }
        let previous = SelectObject(context, UnsafeMutableRawPointer(bitmap))
        defer { _ = SelectObject(context, previous) }
        guard DrawIconEx(context, 0, 0, icon, Int32(side), Int32(side), 0, nil, UINT(DI_NORMAL)) else { return nil }
        _ = GdiFlush()
        var pixels = Array(UnsafeBufferPointer(start: raw.assumingMemoryBound(to: UInt8.self), count: side * side * 4))
        // 알파 없는 옛 아이콘: 그려진 픽셀을 불투명으로
        if !stride(from: 3, to: pixels.count, by: 4).contains(where: { pixels[$0] != 0 }) {
            for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index] | pixels[index + 1] | pixels[index + 2] != 0 {
                pixels[index + 3] = 255
            }
        }
        return pixels
    }

    /// 투명 여백을 잘라 가운데 정사각형을 iconSide×iconSide 칸으로 나누고, 칸의 평균 알파가 절반 이상이면 그 칸의
    /// 평균색으로 채움 (맥 AgentHostFinder.dots와 같은 모양: 곧은 알파 RGBA, 알파 0·255)
    static func dots(_ bgra: [UInt8]) -> SpritePixels? {
        let source = renderSide, side = iconSide
        guard bgra.count == source * source * 4 else { return nil }
        var (minX, minY, maxX, maxY) = (source, source, -1, -1)
        for y in 0..<source {
            for x in 0..<source where bgra[(y * source + x) * 4 + 3] > 25 {
                (minX, minY, maxX, maxY) = (min(minX, x), min(minY, y), max(maxX, x), max(maxY, y))
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let length = max(maxX - minX, maxY - minY) + 1
        let originX = minX - (length - (maxX - minX + 1)) / 2
        let originY = minY - (length - (maxY - minY + 1)) / 2
        var rgba = [UInt8](repeating: 0, count: side * side * 4)
        for row in 0..<side {
            for column in 0..<side {
                var sums = (b: 0, g: 0, r: 0, a: 0), count = 0
                for y in (originY + row * length / side)..<max(originY + (row + 1) * length / side, originY + row * length / side + 1) {
                    for x in (originX + column * length / side)..<max(originX + (column + 1) * length / side, originX + column * length / side + 1) {
                        count += 1
                        guard x >= 0, x < source, y >= 0, y < source else { continue }
                        let index = (y * source + x) * 4
                        sums.b += Int(bgra[index]); sums.g += Int(bgra[index + 1]); sums.r += Int(bgra[index + 2]); sums.a += Int(bgra[index + 3])
                    }
                }
                guard count > 0, sums.a * 2 >= count * 255 else { continue }
                // 미리 곱한 합 → 곧은 색
                let target = (row * side + column) * 4
                rgba[target] = UInt8(min(sums.r * 255 / sums.a, 255))
                rgba[target + 1] = UInt8(min(sums.g * 255 / sums.a, 255))
                rgba[target + 2] = UInt8(min(sums.b * 255 / sums.a, 255))
                rgba[target + 3] = 255
            }
        }
        return SpritePixels(width: side, height: side, rgba: rgba)
    }
}
