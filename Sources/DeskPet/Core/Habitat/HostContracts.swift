import Foundation

/// This object is responsible for the per-tick readings only the operating system can give:
/// where the pointer is, how long the user has been idle, how many keys were pressed (count only),
/// whether a microphone is in use, and moving the pointer a pet is holding.
protocol HostSenses: AnyObject {
    /// 전역 좌표 포인터 위치
    var cursor: CGPoint { get }
    /// 마지막 키보드·마우스 입력 후 지난 시간
    func secondsSinceUserInput() -> TimeInterval
    /// 지난 호출 이후 누른 키 수 (어떤 키인지는 모름)
    func newKeyPresses() -> Int
    /// 마이크가 쓰이는 중인지 (통화 중)
    func microphoneInUse() -> Bool
    /// 펫이 쥔 포인터를 옮김 (포인터 장난)
    func moveCursor(to point: CGPoint)
}

/// This object is responsible for drawing the simulation on the screens: one stage per display,
/// redrawn every tick, and taking mouse input only on the display where a pet or item can be grabbed.
protocol PetStage: AnyObject {
    /// 모니터 구성이 바뀌면 무대를 다시 만듦
    func rebuild(for areas: [ScreenArea])
    /// notes: 구겨 던진 알림 더미. discreet: 통화 중이라 일정 제목을 숨길지
    func render(_ pets: [Pet], projectiles: [Projectile], items: [DroppedItem], notes: [CrumpledNotice], discreet: Bool)
    /// 커서가 있는 무대만, 잡을 것이 있을 때 마우스를 받음
    func routeMouse(at cursor: CGPoint, toPets wantsMouse: Bool)
}
