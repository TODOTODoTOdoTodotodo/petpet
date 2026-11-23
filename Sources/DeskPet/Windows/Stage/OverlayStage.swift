import Foundation
import WinSDK

/// This object is responsible for drawing the simulation on Windows: one layered overlay per monitor,
/// rebuilt when the monitor layout changes, and every tick the shared scene's pet drawings placed in each
/// overlay's pixels (feet, mirroring, peeking from behind a window top and transparency as Core decided),
/// with each tangible pet's grab box made clickable, and only the overlay under a grabbable pet taking the mouse.
/// Speech bubbles, hats, weapons and effects come in phase 3.
final class OverlayStage: PetStage {
    private let instance = GetModuleHandleW(nil)
    private let composer = SceneComposer<WinSprite>.forSkins()
    private var areas: [ScreenArea] = []
    private var overlays: [LayeredOverlay] = []
    private var coordinates = WindowsCoordinates.current()
    private(set) var lastDrawings = 0
    /// 펫 전체 투명도 (메뉴의 Opacity)
    var opacity: CGFloat = 1

    func rebuild(for areas: [ScreenArea]) {
        guard areas != self.areas else { return }
        overlays.forEach { $0.close() }
        coordinates = WindowsCoordinates.current()
        self.areas = areas
        overlays = areas.compactMap { area in
            LayeredOverlay(box: coordinates.pixelBox(area.frame, origin: POINT(x: 0, y: 0)), instance: instance)
        }
    }

    func render(_ pets: [Pet], projectiles: [Projectile], items: [DroppedItem], discreet: Bool) {
        let drawings = composer.compose(pets, projectiles: projectiles, items: items, discreet: discreet).pets
        lastDrawings = drawings.count
        // 레이어드 창은 투명 픽셀의 클릭을 넘기므로, 다리 사이처럼 빈 곳도 잡히게 잡기 영역을 칠함 (맥 무대와 같은 판정)
        let grabAreas = pets.filter(\.isTangible).map(\.grabRect).filter { !$0.isNull }
        for overlay in overlays {
            let sprites = drawings.compactMap { drawing -> OverlaySprite? in
                let box = coordinates.pixelBox(drawing.rect, origin: overlay.origin)
                guard !box.intersection(overlay.canvas.bounds).isEmpty else { return nil }
                return OverlaySprite(image: drawing.frame.texture.image, box: box, mirrored: drawing.frame.mirrored,
                                     flipped: drawing.upsideDown, visibleShare: drawing.shownShare, alpha: drawing.alpha * opacity)
            }
            let hitAreas = grabAreas.map { coordinates.pixelBox($0, origin: overlay.origin) }
            overlay.render(sprites, hitAreas: hitAreas)
        }
    }

    func routeMouse(at cursor: CGPoint, toPets wantsMouse: Bool) {
        let pointer = coordinates.screenPoint(cursor)
        for overlay in overlays {
            let inside = pointer.x >= overlay.origin.x && pointer.x < overlay.origin.x + LONG(overlay.canvas.width)
                && pointer.y >= overlay.origin.y && pointer.y < overlay.origin.y + LONG(overlay.canvas.height)
            overlay.catchesMouse = wantsMouse && inside
        }
    }

    /// 무대별 크기와 보이는 픽셀 수 (연기 시험 보고서용)
    var summary: [[String: Any]] {
        overlays.map {
            ["x": Int($0.origin.x), "y": Int($0.origin.y), "width": $0.canvas.width, "height": $0.canvas.height,
             "visiblePixels": $0.canvas.visiblePixelCount]
        }
    }

    func close() {
        overlays.forEach { $0.close() }
        overlays = []
    }
}
