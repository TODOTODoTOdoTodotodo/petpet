import AppKit

/// This object is responsible for turning mouse presses on a pet into a click (poke), a pick-up, drag and throw,
/// or a right-click (control-click) that asks for that pet's menu, and passing a click on a dropped item along.
/// A press becomes a drag only after the mouse moves a few points; releasing without moving is a click.
/// It only sees clicks while the stage under the cursor is taking mouse events (cursor over a pet).
final class PetDragInput {
    private let roster: PetRoster
    private var monitor: Any?
    /// 눌렀지만 아직 끌지 않은 펫과 누른 위치
    private var pressed: (pet: Pet, at: CGPoint)?
    private weak var held: Pet?
    /// 이만큼 움직여야 드래그로 봄
    private let dragThreshold: CGFloat = 4
    /// 드래그 시작·끝 기록
    var onEvent: ((String) -> Void)?
    /// 펫이 아닌 곳을 눌렀을 때 그 자리 물건 클릭으로 넘김 (물건이었으면 true)
    var onItemClick: ((CGPoint) -> Bool)?
    /// 펫을 우클릭(또는 control 클릭)했을 때
    var onContextMenu: ((Pet, CGPoint) -> Void)?

    init(roster: PetRoster) {
        self.roster = roster
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    var isHolding: Bool { held != nil || pressed != nil }

    private func handle(_ event: NSEvent) {
        let cursor = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown where event.modifierFlags.contains(.control), .rightMouseDown:
            guard let pet = roster.pet(at: cursor) else { return }
            onContextMenu?(pet, cursor)

        case .leftMouseDown:
            guard let pet = roster.pet(at: cursor) else {
                _ = onItemClick?(cursor)
                return
            }
            pressed = (pet, cursor)

        case .leftMouseDragged:
            if let press = pressed, hypot(cursor.x - press.at.x, cursor.y - press.at.y) >= dragThreshold {
                pressed = nil
                held = press.pet
                press.pet.beginDrag(grabbedAt: press.at)
                onEvent?("✋ [\(press.pet.id)] picked up")
            }
            held?.drag(to: cursor)

        case .leftMouseUp:
            if let press = pressed {
                pressed = nil
                press.pet.poke()
                onEvent?("👆 [\(press.pet.id)] poked")
            } else if let pet = held {
                pet.drag(to: cursor)
                pet.endDrag()
                held = nil
                onEvent?("🫳 [\(pet.id)] released")
            }

        default:
            break
        }
    }
}
