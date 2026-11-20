import AppKit

/// This object is responsible for putting the mouse pointer where a pet holding it says, converting global Cocoa
/// coordinates to Quartz ones. It turns off the short input freeze macOS applies after a warp, so the user's own
/// mouse movement is never swallowed and can take the pointer back at once.
final class CursorMover {
    private var reported = false

    init() {
        // 옮긴 직후 0.25초 동안 사용자 마우스 입력을 무시하는 기본 동작을 끔
        CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0
    }

    func move(to point: CGPoint) {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        let result = CGWarpMouseCursorPosition(CGPoint(x: point.x, y: primaryHeight - point.y))
        // 처음 한 번만 결과 기록 (권한 없이 되는지 확인용)
        if !reported {
            reported = true
            PetLogger.shared.log("🖱️ pointer move \(result == .success ? "works" : "failed (\(result.rawValue))")")
        }
    }
}
