import Foundation
import WinSDK

/// This object is responsible for feeding the overlays' Win32 mouse messages into the shared `PetPointerGesture`:
/// left press, drag and release (holding the mouse capture so a drag keeps working off the overlay), right press
/// as the secondary press, and keeping clicks on a pet from activating the overlay or stealing focus.
/// Overlays only get these messages while they take the mouse (pointer over a grabbable pet).
final class OverlayPointerInput {
    private let gesture: PetPointerGesture

    init(gesture: PetPointerGesture) {
        self.gesture = gesture
    }

    /// 처리한 메시지면 결과, 아니면 nil (기본 처리로 넘김)
    func handle(_ window: HWND, _ message: UINT) -> LRESULT? {
        switch message {
        case UINT(WM_MOUSEACTIVATE):
            // 펫을 눌러도 앞 창의 포커스를 빼앗지 않음
            return LRESULT(MA_NOACTIVATE)
        case UINT(WM_LBUTTONDOWN):
            _ = SetCapture(window)
            gesture.primaryDown(at: cursor)
        case UINT(WM_MOUSEMOVE):
            guard gesture.isHolding else { return nil }
            gesture.dragged(to: cursor)
        case UINT(WM_LBUTTONUP):
            // 놓기를 먼저 알림: 캡처를 풀면 WM_CAPTURECHANGED가 곧바로 옴
            gesture.primaryUp(at: cursor)
            _ = ReleaseCapture()
        case UINT(WM_CAPTURECHANGED):
            // 다른 창이 캡처를 가져가면(경고 창 등) 그 자리에서 놓은 것으로 봄
            if gesture.isHolding { gesture.primaryUp(at: cursor) }
        case UINT(WM_RBUTTONDOWN):
            gesture.secondaryDown(at: cursor)
        default:
            return nil
        }
        return 0
    }

    /// 메시지 좌표 대신 화면 커서 위치 (맥 `NSEvent.mouseLocation`과 같은 전역 좌표)
    private var cursor: CGPoint {
        var point = POINT()
        _ = GetCursorPos(&point)
        return WindowsCoordinates.current().point(point)
    }
}
