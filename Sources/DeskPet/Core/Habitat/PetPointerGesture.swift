import Foundation

/// This object is responsible for turning raw pointer presses on pets into a click (poke), a pick-up, drag and throw,
/// or a request for that pet's menu, and passing a press on empty space along as a possible item click.
/// A press becomes a drag only after the pointer moves `dragThreshold` points; releasing without moving is a click.
/// Platform shells feed it their own mouse events (macOS `NSEvent`, Windows window messages).
final class PetPointerGesture {
    /// 이만큼 움직여야 드래그로 봄
    static let dragThreshold: CGFloat = 4

    private let roster: PetRoster
    /// 눌렀지만 아직 끌지 않은 펫과 누른 위치
    private var pressed: (pet: Pet, at: CGPoint)?
    private weak var held: Pet?
    /// 드래그 시작·끝 기록
    var onEvent: ((String) -> Void)?
    /// 펫이 아닌 곳을 눌렀을 때 그 자리 물건 클릭으로 넘김 (물건이었으면 true)
    var onItemClick: ((CGPoint) -> Bool)?
    /// 펫을 보조 버튼으로 눌렀을 때 (맥 우클릭·control 클릭, 윈도우 우클릭)
    var onContextMenu: ((Pet, CGPoint) -> Void)?

    init(roster: PetRoster) {
        self.roster = roster
    }

    /// 누르고 있거나 들고 있는 동안은 커서가 펫을 벗어나도 마우스를 계속 받아야 함
    var isHolding: Bool { held != nil || pressed != nil }

    func primaryDown(at point: CGPoint) {
        guard let pet = roster.pet(at: point) else {
            _ = onItemClick?(point)
            return
        }
        pressed = (pet, point)
    }

    func dragged(to point: CGPoint) {
        if let press = pressed, hypot(point.x - press.at.x, point.y - press.at.y) >= Self.dragThreshold {
            pressed = nil
            held = press.pet
            press.pet.beginDrag(grabbedAt: press.at)
            onEvent?("✋ [\(press.pet.id)] picked up")
        }
        held?.drag(to: point)
    }

    func primaryUp(at point: CGPoint) {
        if let press = pressed {
            pressed = nil
            press.pet.poke()
            onEvent?("👆 [\(press.pet.id)] poked")
        } else if let pet = held {
            pet.drag(to: point)
            pet.endDrag()
            held = nil
            onEvent?("🫳 [\(pet.id)] released")
        }
    }

    func secondaryDown(at point: CGPoint) {
        guard let pet = roster.pet(at: point) else { return }
        onContextMenu?(pet, point)
    }
}
