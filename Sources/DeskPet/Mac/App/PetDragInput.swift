import AppKit

/// This object is responsible for feeding macOS mouse events on the stages into the shared `PetPointerGesture`:
/// left press, drag and release, and right-click or control-click as the secondary press.
/// It only sees clicks while the stage under the cursor is taking mouse events (cursor over a pet).
final class PetDragInput {
    private let gesture: PetPointerGesture
    private var monitor: Any?

    init(gesture: PetPointerGesture) {
        self.gesture = gesture
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func handle(_ event: NSEvent) {
        let cursor = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown where event.modifierFlags.contains(.control), .rightMouseDown:
            gesture.secondaryDown(at: cursor)
        case .leftMouseDown:
            gesture.primaryDown(at: cursor)
        case .leftMouseDragged:
            gesture.dragged(to: cursor)
        case .leftMouseUp:
            gesture.primaryUp(at: cursor)
        default:
            break
        }
    }
}
