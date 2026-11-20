import AppKit
import CoreGraphics

/// This object is responsible for reading displays and visible app windows from macOS
/// and converting Quartz window bounds into global Cocoa coordinates.
final class SystemDesktop: DesktopSource {
    private let ownPID = getpid()
    /// 발판으로 쓰지 않을 시스템 창 주인
    private let ignoredOwners: Set<String> = ["Window Server", "Dock", "DeskPet"]
    /// 이보다 작은 창은 시스템 투명 레이어로 보고 제외
    private let minimumWindowSide: CGFloat = 100

    func displays() -> [ScreenArea] {
        NSScreen.screens.compactMap(Self.area(of:))
    }

    func windows() -> [WindowSnapshot] {
        // Quartz 좌표는 주 모니터(메뉴바 있는 화면) 왼쪽 위가 원점
        guard let primaryHeight = NSScreen.screens.first?.frame.height,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        return list.compactMap { info -> WindowSnapshot? in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let id = info[kCGWindowNumber as String] as? UInt32,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
                  bounds.width >= minimumWindowSide, bounds.height >= minimumWindowSide
            else { return nil }

            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            if ignoredOwners.contains(owner) { return nil }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.1 { return nil }

            let frame = CGRect(
                x: bounds.minX,
                y: primaryHeight - bounds.maxY,
                width: bounds.width,
                height: bounds.height
            )
            return WindowSnapshot(id: id, owner: owner, frame: frame, processID: pid)
        }
    }

    func frontmostApp() -> FrontApp? {
        NSWorkspace.shared.frontmostApplication.map { FrontApp(processID: $0.processIdentifier, bundleID: $0.bundleIdentifier) }
    }

    /// NSScreen을 전역 좌표 모니터 정보로 변환
    static func area(of screen: NSScreen) -> ScreenArea? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        return ScreenArea(
            id: number,
            name: screen.localizedName,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            backingScale: screen.backingScaleFactor
        )
    }
}
