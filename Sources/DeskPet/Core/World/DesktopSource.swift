import Foundation

/// This object is responsible for supplying the current displays and visible windows,
/// so the simulation can run against the real desktop (macOS, Windows) or a scripted one.
/// Every frame is in the shared global coordinates: origin at the primary display's bottom-left, +y up.
protocol DesktopSource: AnyObject {
    func displays() -> [ScreenArea]
    /// 앞에서 뒤 순서의 창 목록
    func windows() -> [WindowSnapshot]
    /// 사용자가 보고 있는 맨 앞 앱
    func frontmostApp() -> FrontApp?
}

/// 맨 앞 앱의 프로세스 ID와 앱 식별자 (맥은 번들 ID, 윈도우는 실행 파일 이름)
struct FrontApp: Equatable {
    let processID: Int32
    let bundleID: String?
}
